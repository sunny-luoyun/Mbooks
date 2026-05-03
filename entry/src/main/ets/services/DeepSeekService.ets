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
    return (charCount / 536000);
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
      : `你是专业日文小说翻译。将以下日文准确、流畅地译成中文，严格保留原文段落与标点格式，不生硬直译。只输出译文，不附加解释。`;

    // ★ 添加固定前缀，使所有 user 消息开头一致，便于缓存命中
    const PREFIX = '请将以下日文翻译成中文：\n';
    const userPrompt = PREFIX + text;

    const messages: DeepSeekMessage[] = [
      { role: 'system', content: systemPrompt } as DeepSeekMessage,
      { role: 'user',   content: userPrompt  } as DeepSeekMessage
    ];

    const requestBody: DeepSeekRequestBody = {
      model: this.model,
      messages: messages,
      temperature: isTitle ? 0.8 : 1.3,
      max_tokens: isTitle ? 100 : 8000
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
    const controller = new AdaptiveConcurrencyController();

    // 辅助函数：处理单个段落并统计
    const handleParagraph = async (index: number): Promise<void> => {
      const text = paragraphs[index];
      if (!text.trim()) {
        results[index] = { success: true, translatedText: '' };
      } else {
        try {
          results[index] = await this.translateText(text, false);
        } catch (e) {
          results[index] = { success: false, error: '未知异常' };
        }
      }
      completedCount++;
      onProgress?.(completedCount, total, results[index].translatedText || '');
      // 通知控制器（成功 / 失败分类）
      const res = results[index];
      if (res.success) {
        controller.onSuccess();
      } else {
        // 根据错误信息简单分类
        if (res.error?.includes('频繁')) controller.onFailure('rate_limit');
        else if (res.error?.includes('超时') || res.error?.includes('timeout')) controller.onFailure('timeout');
        else controller.onFailure('other');
      }
    };

    // ── 1. 缓存预热：前两个请求必须串行，且两个都要发送 ──
    if (total >= 2) {
      await handleParagraph(0);
      await handleParagraph(1);
      await new Promise<void>((resolve) => setTimeout(resolve, 5000));
    } else if (total === 1) {
      // 只有一段，直接翻译，无需预热
      await handleParagraph(0);
      return results;
    }

    // ── 2. 剩余段落使用并发调度 ──
    let nextIndex = 2;  // 已预热前两个
    const activePromises = new Set<Promise<void>>();
    let finalResolve: (() => void) | null = null;
    const finalPromise = new Promise<void>((resolve) => { finalResolve = resolve; });

    const dispatchNext = (): void => {
      while (activePromises.size < controller.getCurrentWindow() && nextIndex < total) {
        const index = nextIndex++;
        let p: Promise<void> = handleParagraph(index)
          .catch((err: Error) => console.error(`段落 ${index} 异常:`, err.message))
          .finally(() => {
            activePromises.delete(p);
            dispatchNext();
          });
        activePromises.add(p);
      }
      if (nextIndex >= total && activePromises.size === 0) {
        finalResolve?.();
      }
    };

    // 预热完成后启动并发调度
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