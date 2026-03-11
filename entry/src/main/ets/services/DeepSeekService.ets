// entry/src/main/ets/services/DeepSeekService.ets

import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';

// ========================================
// 翻译结果接口
// ========================================
interface StatsResult {
  totalChars: number;
  totalRequests: number;
}

export interface TranslationUsage {
  totalChars: number;
  estimatedCost?: number;
}

export interface TranslationResult {
  success: boolean;
  translatedText?: string;
  error?: string;
  usage?: TranslationUsage;
}

// ========================================
// DeepSeek API 响应接口
// ========================================
interface DeepSeekRequestBody {
  model: string;
  messages: DeepSeekMessage[];
  temperature: number;
  max_tokens: number;
}

interface DeepSeekMessage {
  role: string;
  content: string;
}

interface DeepSeekChoice {
  index: number;
  message: DeepSeekMessage;
  finish_reason: string;
}

interface DeepSeekUsage {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
}

interface DeepSeekResponse {
  id: string;
  choices: DeepSeekChoice[];
  usage: DeepSeekUsage;
}

interface DeepSeekBalanceInfo {
  currency: string;
  total_balance: string;
  granted_balance: string;
  topped_up_balance: string;
}

interface DeepSeekBalanceResp {
  is_available: boolean;
  balance_infos: DeepSeekBalanceInfo[];
}

interface BalanceFetchResult {
  success: boolean;
  data: string;
  error: string;
}
// ========================================
// 自适应并发控制器
// ========================================
class AdaptiveConcurrencyController {
  private windowSize: number = 5;
  private readonly minWindow: number = 1;
  private readonly maxWindow: number = 50;
  private readonly successIncrement: number = 1;
  private readonly failureDecrementFactor: number = 2;
  private consecutiveSuccess: number = 0;

  getCurrentWindow(): number {
    return this.windowSize;
  }

  onSuccess(): void {
    this.consecutiveSuccess++;
    if (this.consecutiveSuccess >= 3) {
      this.windowSize = Math.min(this.windowSize + this.successIncrement, this.maxWindow);
      this.consecutiveSuccess = 0;
    }
  }

  onFailure(errorType: 'rate_limit' | 'timeout' | 'other'): void {
    this.consecutiveSuccess = 0;
    switch (errorType) {
      case 'rate_limit':
        this.windowSize = Math.max(this.minWindow, Math.floor(this.windowSize / this.failureDecrementFactor));
        break;
      case 'timeout':
        this.windowSize = Math.max(this.minWindow, this.windowSize - 2);
        break;
      default:
        break;
    }
  }
}

// ========================================
// 主服务类
// ========================================

export class DeepSeekService {
  private apiKey: string = '';
  private baseUrl: string = 'https://api.deepseek.com/v1/chat/completions';
  private model: string = 'deepseek-chat';

  private totalTranslatedChars: number = 0;
  private totalRequests: number = 0;

  constructor(apiKey: string = '') {
    this.apiKey = apiKey;
  }

  updateApiKey(apiKey: string): void {
    this.apiKey = apiKey;
  }

  hasValidKey(): boolean {
    return this.apiKey.length > 0 && this.apiKey.trim().length > 0;
  }

  getStats(): StatsResult {
    return {
      totalChars: this.totalTranslatedChars,
      totalRequests: this.totalRequests
    };
  }

  estimateCost(charCount: number): number {
    return (charCount / 1000) * 0.002;
  }

  /**
   * 查询账户余额
   * GET https://api.deepseek.com/user/balance
   */
  async fetchBalance(apiKey?: string): Promise<BalanceFetchResult> {
    const key = apiKey ?? (AppStorage.get('deepseekApiKey') as string) ?? '';
    if (!key.trim()) {
      // ✅ 使用显式类型的对象字面量
      const failResult: BalanceFetchResult = { success: false, data: '', error: '未配置 API 密钥' };
      return failResult;
    }
    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(
        'https://api.deepseek.com/user/balance',
        {
          method: http.RequestMethod.GET,
          header: {
            'Accept': 'application/json',
            'Authorization': `Bearer ${key}`
          },
          connectTimeout: 10000,
          readTimeout: 10000
        }
      );
      httpRequest.destroy();

      if (response.responseCode === 200) {
        // ✅ 使用顶层声明的接口，不在函数体内声明 interface
        const body = JSON.parse(response.result as string) as DeepSeekBalanceResp;
        let total = '0';
        // 优先取 CNY，没有则取第一条
        for (let i = 0; i < body.balance_infos.length; i++) {
          if (body.balance_infos[i].currency === 'CNY') {
            total = body.balance_infos[i].total_balance;
            break;
          }
        }
        if (total === '0' && body.balance_infos.length > 0) {
          total = body.balance_infos[0].total_balance;
        }
        const okResult: BalanceFetchResult = { success: true, data: total, error: '' };
        return okResult;
      } else {
        const httpFailResult: BalanceFetchResult = {
          success: false,
          data: '',
          error: `HTTP ${response.responseCode}`
        };
        return httpFailResult;
      }
    } catch (e) {
      const catchResult: BalanceFetchResult = {
        success: false,
        data: '',
        error: String(e)
      };
      return catchResult;
    }
  }

  async translateText(text: string, isTitle: boolean = false): Promise<TranslationResult> {
    if (!this.hasValidKey()) {
      return {
        success: false,
        error: '请先在设置中填入 DeepSeek API 密钥'
      };
    }

    if (!text || text.trim().length === 0) {
      return {
        success: false,
        error: '翻译文本不能为空'
      };
    }

    const systemPrompt = isTitle
      ? `你是一个专业的日文翻译。请将以下日文标题翻译成中文。
要求：
1. 保持原标题的风格和意境
2. 如果标题包含专有名词（人名、地名等），使用常见译名
3. 翻译要简洁准确
4. 只返回翻译后的中文标题，不要添加任何解释`
      : `你是一个专业的多语言小说翻译专家。请将以下小说内容（无论原文是何种语言：日文、英文、韩文、法文、俄文等）全部翻译成**简体中文**。

翻译要求：
1. 保持原文的风格、语气和情感
2. 人物对话要自然流畅，符合中文阅读习惯
3. 专有名词（人名、地名、组织名等）保持一致性，使用常见的简体中文译名
4. 中文表达要地道，避免生硬的直译
5. 保留原文的段落格式和换行
6. 如果遇到拟声词，用中文常见的表达方式
7. 保持原文的标点符号使用习惯
8. 严格使用简体中文（绝不出现繁体字）

只返回翻译后的**简体中文**内容，不要添加任何解释、说明、前言、后记或额外内容。`;

    const userPrompt = text;

    const messages: DeepSeekMessage[] = [
      { role: 'system', content: systemPrompt } as DeepSeekMessage,
      { role: 'user',   content: userPrompt  } as DeepSeekMessage
    ];

    const requestBody: DeepSeekRequestBody = {
      model: this.model,
      messages: messages,
      temperature: isTitle ? 0.8 : 1.3,
      max_tokens: isTitle ? 100 : 4000
    };

    const httpRequest = http.createHttp();

    try {
      const response = await httpRequest.request(this.baseUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`
        },
        extraData: JSON.stringify(requestBody),
        connectTimeout: 30000,
        readTimeout: 60000
      });

      const code = response.responseCode;

      if (code === 401 || code === 403) {
        return {
          success: false,
          error: 'API 密钥无效或已过期，请在设置中重新填入'
        };
      }

      if (code === 429) {
        return {
          success: false,
          error: '请求过于频繁，请稍后再试'
        };
      }

      if (code !== 200) {
        return {
          success: false,
          error: `翻译服务请求失败（HTTP ${code}）`
        };
      }

      const raw = response.result as string;
      const data = JSON.parse(raw) as DeepSeekResponse;

      if (data.choices && data.choices.length > 0) {
        const translated = data.choices[0].message.content;

        this.totalRequests++;
        this.totalTranslatedChars += text.length;

        console.info(`[DeepSeek][translateText] 返回内容前50字: ${translated?.substring(0, 50)}`);

        return {
          success: true,
          translatedText: translated,
          usage: {
            totalChars: text.length,
            estimatedCost: this.estimateCost(text.length)
          }
        };
      } else {
        return {
          success: false,
          error: '翻译服务返回空结果'
        };
      }

    } catch (err) {
      const error = err as BusinessError;
      let errorMsg = '网络错误，请检查后重试';

      switch (error.code) {
        case 2300006:
          errorMsg = '无法连接网络，请检查网络设置';
          break;
        case 2300007:
        case 2300028:
          errorMsg = '连接超时，请检查网络后重试';
          break;
        default:
          errorMsg = `翻译失败：${error.message || '未知错误'}`;
      }

      return {
        success: false,
        error: errorMsg
      };
    } finally {
      httpRequest.destroy();
    }
  }

  // ========================================
  // 翻译段落（并发版）
  // ========================================
  async translateParagraphs(
    paragraphs: string[],
    onProgress?: (current: number, total: number, translated: string) => void
  ): Promise<TranslationResult[]> {
    const total = paragraphs.length;
    if (total === 0) return [];

    const results: TranslationResult[] = new Array(total);
    let completedCount = 0;
    let nextIndex = 0;
    const activePromises = new Set<Promise<void>>();
    const controller = new AdaptiveConcurrencyController();

    let finalResolve: (() => void) | null = null;
    const finalPromise = new Promise<void>((resolve) => {
      finalResolve = resolve;
    });

    // ✅ 修复1：明确返回类型 Promise<void>，移除内部对 activePromise 的引用
    const processParagraph = async (index: number): Promise<void> => {
      const text = paragraphs[index];
      let result: TranslationResult;

      if (!text.trim()) {
        result = { success: true, translatedText: '' };
      } else {
        try {
          result = await this.translateText(text, false);
          if (result.success) {
            controller.onSuccess();
          } else {
            if (result.error?.includes('请求过于频繁')) {
              controller.onFailure('rate_limit');
            } else if (result.error?.includes('超时') || result.error?.includes('timeout')) {
              controller.onFailure('timeout');
            } else {
              controller.onFailure('other');
            }
          }
        } catch (e) {
          result = { success: false, error: '未知异常' };
          controller.onFailure('other');
        }
      }

      results[index] = result;
      completedCount++;
      onProgress?.(completedCount, total, result.translatedText || '');
      // 注意：不在这里 delete，交给 dispatchNext 里的 finally 处理
    };

    // ✅ 修复2：在 dispatchNext 里用局部变量 p 持有 Promise 引用，
    //          通过 .finally() 删除，彻底消除 activePromise 作用域问题；
    //          .catch 回调参数显式标注 Error 类型，消除 any/unknown 报错
    const dispatchNext = (): void => {
      while (activePromises.size < controller.getCurrentWindow() && nextIndex < total) {
        const index = nextIndex++;

        // 先声明变量，再赋值，让 finally 闭包可以正确捕获
        let p: Promise<void>;
        p = processParagraph(index)
          .catch((err: Error): void => {
            // ✅ err 显式声明为 Error，解决 arkts-no-any-unknown 报错
            console.error(`段落 ${index} 处理异常: ${err.message}`);
          })
          .finally((): void => {
            // ✅ 在这里删除自身引用，完全不依赖外部 activePromise 变量
            activePromises.delete(p);
            // 每次有任务完成，都尝试继续派发或判断是否全部完成
            dispatchNext();
          });

        activePromises.add(p);
      }

      // 所有段落已派发且无活跃请求 → 全部完成
      if (nextIndex >= total && activePromises.size === 0) {
        finalResolve?.();
      }
    };

    dispatchNext();

    await finalPromise;
    return results;
  }
}

// ========================================
// 单例工厂（配合 AppStorage 中的 API Key）
// ========================================

let _deepSeekInstance: DeepSeekService | null = null;

export function getDeepSeekService(): DeepSeekService {
  const apiKey = AppStorage.get<string>('deepseekApiKey') ?? '';
  if (!_deepSeekInstance) {
    _deepSeekInstance = new DeepSeekService(apiKey);
  } else {
    _deepSeekInstance.updateApiKey(apiKey);
  }
  return _deepSeekInstance;
}