// entry/src/main/ets/services/PixivService.ets

import http from '@ohos.net.http';
import {
  PixivNovel,
  PixivSearchParams,
  PixivSearchResult,
  PixivSortOrder,
  PixivContentMode,
  CacheStatus,
  parsePixivNovelFromRaw,
  RawPixivNovelItem,
  PixivSeries,
  PixivTag,
  PixivSearchMode
} from '../models/PixivModels';

// ========================================
// 常量
// ========================================

const BASE_URL   = 'https://www.pixiv.net';
const AJAX_BASE  = `${BASE_URL}/ajax`;

// 请求超时（毫秒）
const TIMEOUT_SEARCH   = 10000;
const TIMEOUT_FETCH    = 15000;

// 每页结果数（Pixiv 固定 60 条）
const PAGE_SIZE = 60;

// ========================================
// 内部类型：统一 HTTP 响应结构
// ========================================

// Pixiv Ajax API 统一外层结构
interface PixivAjaxResponse<T> {
  error:   boolean;
  message: string;
  body:    T;
}
// 搜索接口 body 结构
interface NovelSearchData {
  data:  object[];  // 原始小说列表
  total: number;    // 命中总数
}

interface SearchResponseBody {
  novel: NovelSearchData;
}
// 小说详情接口 body 结构
interface TagTranslation {
  en?: string;
  zh?: string;
}

interface TagItem {
  tag:         string;
  translation?: TagTranslation;
}

interface TagsData {
  tags: Array<TagItem>;
}

interface SeriesNavData {
  seriesId:    number;
  title:       string;
  order:       number;
}

interface NovelDetailBody {
  id:          string;
  title:       string;
  content:     string;  // 正文
  description: string;
  userId:      string;
  userName:    string;
  tags:        TagsData;
  createDate:    string;
  uploadDate:    string;
  bookmarkCount: number;
  viewCount:     number;
  commentCount:  number;
  pageCount:     number;
  wordCount:     number;
  seriesNavData?: SeriesNavData;
  coverUrl:      string;
}

// ========================================
// 请求结果包装（统一处理成功/失败）
// ========================================

export interface ServiceResult<T> {
  success: boolean;
  data?:   T;
  error?:  string;       // 用户可读的错误描述
  code?:   number;       // HTTP 状态码（网络错误时有值）
}

// ========================================
// 主服务类
// ========================================

export class PixivService {

  private phpSessionId: string;

  constructor(phpSessionId: string) {
    this.phpSessionId = phpSessionId;
  }

  // 动态更新 Cookie（用户在设置页修改后调用）
  updateSession(phpSessionId: string): void {
    this.phpSessionId = phpSessionId;
  }

  // ========================================
  // 公开 API
  // ========================================

  /**
   * 搜索小说
   * @param params 搜索参数
   * @returns 搜索结果（含分页信息）
   */
  async searchNovels(params: PixivSearchParams): Promise<ServiceResult<PixivSearchResult>> {
    const keyword = params.keyword;
    const page = params.page ?? 1;
    const order = params.order ?? PixivSortOrder.DATE_DESC;
    const mode = params.mode ?? PixivContentMode.ALL;
    const sMode   = params.searchMode ?? PixivSearchMode.TAG_ONLY;  // ← 新增，默认 s_tag

    if (!keyword.trim()) {
      return { success: false, error: '搜索关键词不能为空' };
    }

    const encoded = encodeURIComponent(keyword);
    const url =
      `${AJAX_BASE}/search/novels/${encoded}` +
        `?word=${encoded}` +
        `&order=${order}` +
        `&mode=${mode}` +
        `&s_mode=${sMode}` +
        `&include_translated_tags=1` +
        `&p=${page}` +
        `&type=novel` +
        `&lang=zh`;

    const resp = await this.get<PixivAjaxResponse<SearchResponseBody>>(url, TIMEOUT_SEARCH);
    if (!resp.success || !resp.data) {
      return { success: false, error: resp.error, code: resp.code };
    }

    if (resp.data.error) {
      // Pixiv 接口层面返回错误（如未登录）
      return {
        success: false,
        error: this.translatePixivError(resp.data.message)
      };
    }

    const body    = resp.data.body;
    const rawList = body?.novel?.data  ?? [];
    const total   = body?.novel?.total ?? 0;
    const novels: PixivNovel[] = rawList.map(
      (raw: object) => parsePixivNovelFromRaw(raw as RawPixivNovelItem)
    );

    return {
      success: true,
      data: {
        novels,
        total,
        currentPage: page,
        hasMore:     page * PAGE_SIZE < total,
        keyword
      }
    };
  }

  /**
   * 获取小说正文（用于离线缓存）
   * @param novelId 小说 ID
   * @returns 正文字符串
   */
  async fetchNovelText(novelId: string): Promise<ServiceResult<string>> {
    if (!novelId) {
      return { success: false, error: '小说 ID 不能为空' };
    }

    const url = `${AJAX_BASE}/novel/${novelId}`;
    const resp = await this.get<PixivAjaxResponse<NovelDetailBody>>(url, TIMEOUT_FETCH);

    if (!resp.success || !resp.data) {
      return { success: false, error: resp.error, code: resp.code };
    }
    if (resp.data.error) {
      return {
        success: false,
        error: this.translatePixivError(resp.data.message)
      };
    }

    const content = resp.data.body?.content ?? '';
    if (!content) {
      return { success: false, error: '正文内容为空，可能需要登录后访问' };
    }

    return { success: true, data: content };
  }

  /**
   * 获取小说完整元数据（含正文字段，比搜索接口更详细）
   * @param novelId 小说 ID
   */
  async fetchNovelDetail(novelId: string): Promise<ServiceResult<PixivNovel>> {
    const url = `${AJAX_BASE}/novel/${novelId}`;
    const resp = await this.get<PixivAjaxResponse<NovelDetailBody>>(url, TIMEOUT_FETCH);

    if (!resp.success || !resp.data) {
      return { success: false, error: resp.error, code: resp.code };
    }
    if (resp.data.error) {
      return {
        success: false,
        error: this.translatePixivError(resp.data.message)
      };
    }

    const b = resp.data.body;
    const novel: PixivNovel = {
      id:            b.id,
      title:         b.title,
      caption:       b.description ?? '',
      author:        b.userName,
      authorId:      b.userId,
      coverUrl:      b.coverUrl ?? '',
      tags:          (b.tags?.tags ?? []).map(t => ({
        name:        t.tag,
        translation: t.translation?.zh ?? t.translation?.en ?? undefined
      } as PixivTag)),
      textLength:    b.wordCount  ?? 0,
      pageCount:     b.pageCount  ?? 1,
      createDate:    b.createDate ?? '',
      updateDate:    b.uploadDate ?? '',
      series: b.seriesNavData ? {
        id:    String(b.seriesNavData.seriesId),
        title: b.seriesNavData.title,
        order: b.seriesNavData.order
      } as PixivSeries : undefined,
      bookmarkCount: b.bookmarkCount ?? 0,
      viewCount:     b.viewCount     ?? 0,
      commentCount:  b.commentCount  ?? 0,
      cacheStatus:   CacheStatus.NOT_CACHED,
      fullText:      b.content ?? undefined
    };

    return { success: true, data: novel };
  }

  /**
   * 构造 Pixiv 小说阅读页 URL（WebView 打开）
   */
  getNovelWebUrl(novelId: string): string {
    return `${BASE_URL}/novel/show.php?id=${novelId}`;
  }

  /**
   * 校验当前 Cookie 是否有效（登录状态检测）
   * 原理：请求一个需要登录才能返回完整数据的接口
   */
  async checkLogin(): Promise<ServiceResult<boolean>> {
    if (!this.phpSessionId) {
      return { success: true, data: false, error: 'PHPSESSID 未填写' };
    }

    // 换一个更稳定的接口，或者直接试获取小说接口
    const url = `${AJAX_BASE}/user/extra`;
    const resp = await this.get<PixivAjaxResponse<object>>(url, TIMEOUT_SEARCH);

    // ✅ 区分网络失败 vs Cookie 失效
    if (!resp.success) {
      // code 存在表示 HTTP 层的 401/403，是真正的 Cookie 失效
      if (resp.code === 401 || resp.code === 403) {
        return { success: true, data: false, error: 'Cookie 已失效' };
      }
      // 没有 code 则是网络层错误（超时/SSL失败），不能判定 Cookie 失效
      return { success: false, error: resp.error };  // 告知调用方是网络问题
    }

    return { success: true, data: !resp.data?.error };
  }

  // ========================================
  // 私有：底层 HTTP 封装
  // ========================================

  /**
   * 发起 GET 请求，统一处理 Cookie / Header / 超时 / 错误
   */
  private async get<T>(url: string, timeout: number): Promise<ServiceResult<T>> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method:           http.RequestMethod.GET,
        connectTimeout:   timeout,
        readTimeout:      timeout,
        header: {
          'Cookie':       this.buildCookieHeader(),
          'User-Agent':   this.getUserAgent(),
          'Referer':      BASE_URL + '/',
          'Accept':       'application/json',
          'Accept-Language': 'zh-CN,zh;q=0.9,ja;q=0.8',
          // Pixiv 部分接口需要这个头，否则返回 400
          'x-user-id':   this.getUserIdFromCookie()
        }
      });

      const code = response.responseCode;

      // 处理常见 HTTP 错误
      if (code === 401 || code === 403) {
        return {
          success: false,
          error:   'Cookie 已失效，请在设置中重新填入 PHPSESSID',
          code
        };
      }
      if (code === 404) {
        return { success: false, error: '内容不存在或已被删除', code };
      }
      if (code === 429) {
        return { success: false, error: '请求过于频繁，请稍后再试', code };
      }
      if (code !== 200) {
        return { success: false, error: `请求失败（HTTP ${code}）`, code };
      }

      // 解析 JSON
      const raw = response.result as string;
      if (!raw) {
        return { success: false, error: '服务器返回空响应' };
      }

      try {
        const data = JSON.parse(raw) as T;
        return { success: true, data };
      } catch {
        return { success: false, error: 'JSON 解析失败，返回内容格式异常' };
      }

    } catch (err) {
      // 网络层错误（无网络、超时等）
      const msg = this.parseNetworkError(err);
      return { success: false, error: msg };
    } finally {
      // 必须销毁，防止句柄泄漏
      httpRequest.destroy();
    }
  }

  // ========================================
  // 私有：工具方法
  // ========================================

  private buildCookieHeader(): string {
    // 基础匿名 Cookie + 用户登录态
    const base = 'GDPR_NOTICE_SEEN=1; p_ab_id=0; p_ab_id_2=0; p_ab_d_id=0;';
    if (this.phpSessionId) {
      return `${base} PHPSESSID=${this.phpSessionId};`;
    }
    return base;
  }

  // 从 PHPSESSID 提取 userId
  // Pixiv 的 PHPSESSID 格式为：{userId}_xxxxxxxxxxxxx
  private getUserIdFromCookie(): string {
    if (!this.phpSessionId) return '';
    const parts = this.phpSessionId.split('_');
    return parts.length > 0 ? parts[0] : '';
  }

  private getUserAgent(): string {
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ' +
      'AppleWebKit/537.36 (KHTML, like Gecko) ' +
      'Chrome/120.0.0.0 Safari/537.36';
  }

  // 把 Pixiv API 的英文错误消息翻译成用户可读的中文
  private translatePixivError(msg: string): string {
    if (!msg) return '未知错误，请稍后重试';
    const lower = msg.toLowerCase();
    if (lower.includes('not login') || lower.includes('session')) {
      return '未登录或 Cookie 已过期，请在设置中更新 PHPSESSID';
    }
    if (lower.includes('not found') || lower.includes('404')) {
      return '内容不存在或已被删除';
    }
    if (lower.includes('rate limit') || lower.includes('too many')) {
      return '请求过于频繁，请稍后再试';
    }
    return `Pixiv 返回错误：${msg}`;
  }
  // 解析鸿蒙网络错误码为用户可读文字
  private parseNetworkError(err: object): string {
    // 鸿蒙 http 模块错误码
    const code = (err as Record<string, number>)?.code;
    switch (code) {
      case 2300006: return '无法连接网络，请检查网络设置';
      case 2300007: return '请求超时，请检查网络后重试';
      case 2300028: return '连接超时，请检查网络后重试';
      case 2300052: return '服务器拒绝连接，可能需要使用代理';
      default:      return `网络错误（code: ${code ?? '未知'}），请检查网络后重试`;
    }
  }
}

// ========================================
// 节流工具：防止短时间内重复搜索
// ========================================

export class SearchThrottle {
  private lastSearchTime: number = 0;
  private readonly interval: number;  // 毫秒

  constructor(intervalMs: number = 1000) {
    this.interval = intervalMs;
  }

  canSearch(): boolean {
    const now = Date.now();
    if (now - this.lastSearchTime >= this.interval) {
      this.lastSearchTime = now;
      return true;
    }
    return false;
  }

  // 距离下次可搜索还剩多少毫秒
  remainingMs(): number {
    const elapsed = Date.now() - this.lastSearchTime;
    return Math.max(0, this.interval - elapsed);
  }
}

// ========================================
// 单例工厂（配合 AppStorage 中的 Cookie）
// ========================================

let _serviceInstance: PixivService | null = null;

export function getPixivService(): PixivService {
  const cookie = AppStorage.get<string>('pixivSessionId') ?? '';
  if (!_serviceInstance) {
    _serviceInstance = new PixivService(cookie);
  } else {
    // 每次获取时同步最新 Cookie（用户可能在设置页更新了）
    _serviceInstance.updateSession(cookie);
  }
  return _serviceInstance;
}