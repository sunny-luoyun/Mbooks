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
  usage?: TranslationUsage;  // ← 改用具名接口
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

// ========================================
// 主服务类
// ========================================

export class DeepSeekService {
  private apiKey: string = '';
  private baseUrl: string = 'https://api.deepseek.com/v1/chat/completions';
  private model: string = 'deepseek-chat';

  // 统计信息
  private totalTranslatedChars: number = 0;
  private totalRequests: number = 0;

  constructor(apiKey: string = '') {
    this.apiKey = apiKey;
  }

  /**
   * 更新API密钥（用户在设置页修改后调用）
   */
  updateApiKey(apiKey: string): void {
    this.apiKey = apiKey;
  }

  /**
   * 检查API密钥是否有效
   */
  hasValidKey(): boolean {
    return this.apiKey.length > 0 && this.apiKey.trim().length > 0;
  }

  /**
   * 获取统计信息
   */
  getStats(): StatsResult {
    return {
      totalChars: this.totalTranslatedChars,
      totalRequests: this.totalRequests
    };
  }

  /**
   * 估算费用（仅供参考）
   * DeepSeek 价格：约 $0.002 / 1K 字符（请以官方最新价格为准）
   */
  estimateCost(charCount: number): number {
    return (charCount / 1000) * 0.002;
  }

  /**
   * 翻译文本
   * @param text 要翻译的日文文本
   * @param isTitle 是否为标题（标题翻译用不同提示词）
   */
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

    // 构建提示词
    const systemPrompt = isTitle
      ? `你是一个专业的日文翻译。请将以下日文标题翻译成中文。
要求：
1. 保持原标题的风格和意境
2. 如果标题包含专有名词（人名、地名等），使用常见译名
3. 翻译要简洁准确
4. 只返回翻译后的中文标题，不要添加任何解释`
      : `你是一个专业的日文小说翻译。请将以下日文小说内容翻译成中文。

翻译要求：
1. 保持原文的风格、语气和情感
2. 人物对话要自然流畅
3. 专有名词（人名、地名等）保持一致性
4. 中文表达要地道，避免生硬的直译
5. 保留原文的段落格式
6. 如果遇到拟声词，用中文常见的表达方式
7. 保持原文的标点符号使用习惯

只返回翻译后的中文内容，不要添加任何解释或额外内容。`;

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
        connectTimeout: 30000,  // 30秒超时
        readTimeout: 60000       // 60秒读取超时
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

        // 更新统计
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

      // 根据错误码提供更具体的提示
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

  /**
   * 批量翻译多个段落（用于整章翻译）
   * @param paragraphs 段落数组
   * @param onProgress 进度回调
   */
  async translateParagraphs(
    paragraphs: string[],
    onProgress?: (current: number, total: number, translated: string) => void
  ): Promise<TranslationResult[]> {
    const results: TranslationResult[] = [];

    for (let i = 0; i < paragraphs.length; i++) {
      const para = paragraphs[i];
      if (!para.trim()) {
        // 空行保留
        results.push({ success: true, translatedText: '' });
        continue;
      }

      const result = await this.translateText(para, false);
      results.push(result);

      if (onProgress) {
        onProgress(i + 1, paragraphs.length, result.translatedText || '');
      }

      // API调用延迟，避免频率限制
      if (i < paragraphs.length - 1) {
        await new Promise<void>(resolve => setTimeout(resolve, 800));
      }
    }

    return results;
  }
}

// ========================================
// 单例工厂（配合AppStorage中的API Key）
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