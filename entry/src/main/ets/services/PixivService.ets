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
  PixivSearchMode,
  PixivAuthor,
  PixivAuthorSearchResult
} from '../models/PixivModels';

// ========================================
// 常量
// ========================================

const BASE_URL  = 'https://www.pixiv.net';
const AJAX_BASE = `${BASE_URL}/ajax`;

const TIMEOUT_SEARCH = 15000;
const TIMEOUT_FETCH  = 15000;
const PAGE_SIZE      = 48; // ✅ 修复：Pixiv /user/{id}/novels 接口每次最多 48 个ID，超过则 works 返回{}

// ========================================
// 内部类型（全部在顶层声明，ArkTS 不允许方法体内定义 interface）
// ========================================

interface PixivAjaxResponse<T> {
  error:   boolean;
  message: string;
  body:    T;
}

interface FollowingAuthorsResponseBody {
  users: Array<RawPixivUserItem>;
  total: number;
  hasNext: boolean;
}

interface NovelSearchData {
  data:  RawPixivNovelItem[];
  total: number;
}

interface SearchResponseBody {
  novel: NovelSearchData;
}

interface TagTranslation {
  en?: string;
  zh?: string;
}

interface RawPixivUserItem {
  userId:          string;
  userName?:       string;
  name?:           string;
  userAccount?:    string;
  account?:        string;
  profileImageUrl?: string;
  image?:          string;
  isFollowed:      boolean;
  followedBack?:   boolean;
  novelCount?:     number;
  illustCount?:    number;
}

interface SearchUsersPage {
  userIds?: number[];
  workIds?: Record<string, Object>;
}

interface SearchUsersThumbnails {
  users?: Record<string, RawPixivUserItem>;
}

interface SearchUsersResponse {
  users?:       RawPixivUserItem[] | Record<string, RawPixivUserItem>;
  user?:        RawPixivUserItem[];
  illustUsers?: RawPixivUserItem[];
  novelUsers?:  RawPixivUserItem[];
  total?:       number;
  page?:        SearchUsersPage;
  thumbnails?:  SearchUsersThumbnails;
}

interface FollowingNovelPage {
  ids:   number[];
  total: number;
}

interface ProfileAllBody {
  novels:   Record<string, Object | null>;
  illusts?: Record<string, Object | null>;
  manga?:   Record<string, Object | null>;
}

// ✅ 核心修复：从方法体内移到顶层，ArkTS 不支持局部 interface
interface UserNovelsBody {
  works?: Record<string, RawPixivNovelItem>;
}

// 新增这个（紧跟在上面后面）
interface UserNovelsBodyDirect {
  works?: Record<string, RawPixivNovelItem>;
}

interface FollowingNovelThumbnails {
  novel: RawPixivNovelItem[];
}

interface FollowingNovelBody {
  page:       FollowingNovelPage;
  thumbnails: FollowingNovelThumbnails;
}

interface TagItem {
  tag:          string;
  translation?: TagTranslation;
}

interface TagsData {
  tags: Array<TagItem>;
}

interface SeriesNavData {
  seriesId: number;
  title:    string;
  order:    number;
}

interface NovelDetailBody {
  id:             string;
  title:          string;
  content:        string;
  description:    string;
  userId:         string;
  userName:       string;
  tags:           TagsData;
  createDate:     string;
  uploadDate:     string;
  bookmarkCount:  number;
  viewCount:      number;
  commentCount:   number;
  pageCount:      number;
  wordCount:      number;
  seriesNavData?: SeriesNavData;
  coverUrl:       string;
}

// ========================================
// 请求结果包装
// ========================================
export interface ServiceResult<T> {
  success: boolean;
  data?:   T;
  error?:  string;
  code?:   number;
}

interface FollowingAuthorsResult {
  authors: PixivAuthor[];
  total: number;
  hasMore: boolean;
}

// ========================================
// 主服务类
// ========================================

export class PixivService {

  private phpSessionId: string;

  constructor(phpSessionId: string) {
    this.phpSessionId = phpSessionId;
  }

  updateSession(phpSessionId: string): void {
    this.phpSessionId = phpSessionId;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 搜索作者
  // ──────────────────────────────────────────────────────────────────────────

  async searchAuthors(keyword: string, page: number = 1): Promise<ServiceResult<PixivAuthorSearchResult>> {
    if (!keyword.trim()) {
      return { success: false, error: '搜索关键词不能为空' };
    }

    const encoded = encodeURIComponent(keyword);
    const url = `${AJAX_BASE}/search/users?nick=${encoded}&s_mode=s_usr&i=1&p=${page}&lang=zh`;

    console.info(`[PixivService] 搜索作者 URL: ${url}`);

    const resp = await this.get<PixivAjaxResponse<SearchUsersResponse>>(url, TIMEOUT_SEARCH);

    if (!resp.success || !resp.data) {
      console.error(`[PixivService] 搜索作者网络错误: ${resp.error}, code: ${resp.code}`);
      return { success: false, error: resp.error, code: resp.code };
    }

    if (resp.data.error) {
      return { success: false, error: this.translatePixivError(resp.data.message) };
    }

    const body = resp.data.body;

    console.info(`[PixivService] 返回的顶层字段: ${JSON.stringify(Object.keys(body as Object))}`);

    if (body.users) {
      console.info(`[PixivService] body.users 类型: ${Array.isArray(body.users) ? '数组' : typeof body.users}`);
      console.info(`[PixivService] body.users 内容片段: ${JSON.stringify(body.users).substring(0, 300)}`);
    }
    if (body.thumbnails) {
      console.info(`[PixivService] body.thumbnails 字段存在，类型: ${typeof body.thumbnails}`);
    }
    if (body.page?.userIds) {
      console.info(`[PixivService] body.page.userIds: ${JSON.stringify(body.page.userIds)}`);
    }

    let rawUsers: RawPixivUserItem[] = [];
    let total = 0;

    if (body.users) {
      if (Array.isArray(body.users)) {
        rawUsers = body.users as RawPixivUserItem[];
        total = body.total ?? rawUsers.length;
        console.info(`[PixivService] 解析为数组格式，数量: ${rawUsers.length}`);
      } else if (typeof body.users === 'object') {
        rawUsers = Object.values(body.users as Record<string, RawPixivUserItem>);
        total = rawUsers.length;
        console.info(`[PixivService] 解析为对象格式，转换后数量: ${rawUsers.length}`);
      }
    } else if (body.user && Array.isArray(body.user)) {
      rawUsers = body.user;
      total = body.total ?? rawUsers.length;
    } else if (body.illustUsers && Array.isArray(body.illustUsers)) {
      rawUsers = body.illustUsers;
      total = body.total ?? rawUsers.length;
    } else if (body.novelUsers && Array.isArray(body.novelUsers)) {
      rawUsers = body.novelUsers;
      total = body.total ?? rawUsers.length;
    }

    if (rawUsers.length === 0 && body.page?.userIds && body.thumbnails) {
      console.info(`[PixivService] 尝试从 thumbnails 重建用户数据`);
      const userIds: number[] = body.page.userIds;
      const thumbnails = body.thumbnails as SearchUsersThumbnails;
      const thumbUsersMap = thumbnails.users;
      rawUsers = userIds.map((id: number): RawPixivUserItem => {
        const idStr = String(id);
        const thumbUser = thumbUsersMap?.[idStr];
        return {
          userId:          idStr,
          name:            thumbUser?.name            || thumbUser?.userName       || '',
          userName:        thumbUser?.name            || thumbUser?.userName       || '',
          account:         thumbUser?.account         || thumbUser?.userAccount    || '',
          userAccount:     thumbUser?.account         || thumbUser?.userAccount    || '',
          image:           thumbUser?.image           || thumbUser?.profileImageUrl || '',
          profileImageUrl: thumbUser?.image           || thumbUser?.profileImageUrl || '',
          isFollowed:      thumbUser?.isFollowed      || false,
          novelCount:      thumbUser?.novelCount,
          illustCount:     thumbUser?.illustCount
        };
      });
      total = rawUsers.length;
      console.info(`[PixivService] 从 thumbnails 重建了 ${rawUsers.length} 个用户`);
    }

    if (rawUsers.length === 0) {
      console.warn(`[PixivService] 未能解析到任何用户数据`);
    }

    const authors: PixivAuthor[] = rawUsers.map((raw: RawPixivUserItem): PixivAuthor => ({
      id:          raw.userId,
      name:        raw.name        || raw.userName       || '',
      account:     raw.account     || raw.userAccount    || '',
      avatarUrl:   raw.image       || raw.profileImageUrl || '',
      isFollowed:  raw.isFollowed  || raw.followedBack   || false,
      novelCount:  raw.novelCount,
      illustCount: raw.illustCount
    }));

    console.info(`[PixivService] 搜索作者成功: ${authors.length} 个结果`);

    return {
      success: true,
      data: {
        authors,
        total,
        currentPage: page,
        hasMore: authors.length >= 20,
        keyword
      }
    };
  }

  //获取关注列表
  // 在 PixivService 类中添加
  async fetchFollowingAuthors(page: number = 1): Promise<ServiceResult<FollowingAuthorsResult>> {
    const userId = this.getUserIdFromCookie();
    if (!userId) {
      return { success: false, error: '无法获取用户ID，请检查 Cookie 是否有效' };
    }

    const limit = 48;
    const offset = (page - 1) * limit;
    const url = `${AJAX_BASE}/user/${userId}/following?offset=${offset}&limit=${limit}&rest=show&lang=zh`;

    const resp = await this.get<PixivAjaxResponse<FollowingAuthorsResponseBody>>(url, TIMEOUT_SEARCH);
    if (!resp.success || !resp.data) {
      return { success: false, error: resp.error, code: resp.code };
    }
    if (resp.data.error) {
      return { success: false, error: this.translatePixivError(resp.data.message) };
    }

    const body = resp.data.body;
    const rawUsers = body.users || [];
    const authors: PixivAuthor[] = rawUsers.map((raw: RawPixivUserItem): PixivAuthor => ({
      id: raw.userId,
      name: raw.name || raw.userName || '',
      account: raw.account || raw.userAccount || '',
      avatarUrl: raw.image || raw.profileImageUrl || '',
      isFollowed: true,
      novelCount: raw.novelCount,
      illustCount: raw.illustCount,
    }));
    const result: FollowingAuthorsResult = {
      authors,
      total: body.total || authors.length,
      hasMore: body.hasNext || (authors.length >= limit)
    };
    
    return {
      success: true,
      data: result
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 获取作者小说列表
  // ──────────────────────────────────────────────────────────────────────────

  async fetchAuthorNovels(userId: string, page: number = 1): Promise<ServiceResult<PixivSearchResult>> {
    if (!userId) {
      return { success: false, error: '作者ID不能为空' };
    }

    const userPageReferer = `${BASE_URL}/users/${userId}/novels`;

    // ── 第一步：获取该用户所有小说的 ID 列表 ────────────────────────────────

    const profileUrl = `${AJAX_BASE}/user/${userId}/profile/all?lang=zh`;
    const profileResp = await this.getWithReferer<PixivAjaxResponse<ProfileAllBody>>(
      profileUrl, userPageReferer, TIMEOUT_SEARCH
    );

    if (!profileResp.success || !profileResp.data) {
      if (profileResp.code === 403) {
        return { success: false, error: '获取作者资料失败（403），请填入有效的 PHPSESSID', code: 403 };
      }
      return { success: false, error: profileResp.error, code: profileResp.code };
    }
    if (profileResp.data.error) {
      return { success: false, error: this.translatePixivError(profileResp.data.message) };
    }

    const novelsMap = profileResp.data.body?.novels;

    let allIds: string[] = [];
    if (novelsMap && typeof novelsMap === 'object') {
      allIds = Object.keys(novelsMap as object);
    }

    console.info(`[PixivService] 作者 ${userId} 的小说ID数量: ${allIds.length}`);

    if (allIds.length === 0) {
      return {
        success: true,
        data: { novels: [], total: 0, currentPage: page, hasMore: false, keyword: '' }
      };
    }

    // ✅ 修复：ID 按数值降序排列（数值越大 = 越新），保证最新作品显示在前
    allIds.sort((a: string, b: string): number => parseInt(b, 10) - parseInt(a, 10));

    // ── 第二步：分页取对应 ID 的小说详情 ────────────────────────────────────

    const pageIds = allIds.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

    console.info(`[PixivService] 第${page}页 ID范围: ${pageIds[0]}~${pageIds[pageIds.length - 1]}，共${pageIds.length}个`);

    // ✅ 修复：encodeURIComponent 每个 ID，拼成 ids[]=xxx&ids[]=yyy 格式
    const idParams = pageIds.map((id: string): string => `ids[]=${encodeURIComponent(id)}`).join('&');
    const detailUrl = `${AJAX_BASE}/user/${userId}/novels?${idParams}&lang=zh`;

    console.info(`[PixivService] detailUrl 长度: ${detailUrl.length}`);

    // ✅ 核心修复：使用顶层声明的 UserNovelsBody，不再在方法体内定义 interface
    const resp = await this.getWithReferer<PixivAjaxResponse<UserNovelsBody>>(
      detailUrl, userPageReferer, TIMEOUT_SEARCH
    );

    if (!resp.success || !resp.data) {
      console.error(`[PixivService] 获取作者小说详情失败: ${resp.error}, code: ${resp.code}`);
      return { success: false, error: resp.error, code: resp.code };
    }
    if (resp.data.error) {
      console.error(`[PixivService] Pixiv返回错误: ${resp.data.message}`);
      return { success: false, error: this.translatePixivError(resp.data.message) };
    }

    const bodyObj = resp.data.body as Record<string, RawPixivNovelItem>;
    let worksMap: Record<string, RawPixivNovelItem> = {};

    // 先尝试 body.works
    if (resp.data.body?.works && typeof resp.data.body.works === 'object') {
      worksMap = resp.data.body.works;
    }

    // body.works 为空时，直接把 body 本身当 worksMap
    if (Object.keys(worksMap).length === 0) {
      const directMap: Record<string, RawPixivNovelItem> = {};
      const keys = Object.keys(bodyObj as object);
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const val = bodyObj[key];
        if (val && typeof val === 'object' && val.id && val.title) {
          directMap[key] = val;
        }
      }
      worksMap = directMap;
    }

    console.info(`[PixivService] works 解析后键数量: ${worksMap ? Object.keys(worksMap).length : 0}`);

    if (!worksMap || Object.keys(worksMap).length === 0) {
      console.warn(`[PixivService] works 为空，body片段: ${JSON.stringify(resp.data.body).substring(0, 300)}`);
      return {
        success: true,
        data: { novels: [], total: allIds.length, currentPage: page, hasMore: false, keyword: '' }
      };
    }

    const novels: PixivNovel[] = Object.values(worksMap).map(
      (raw: RawPixivNovelItem): PixivNovel => parsePixivNovelFromRaw(raw)
    );

    // 按 ID 降序排序（最新在前）
    novels.sort((a: PixivNovel, b: PixivNovel): number => parseInt(b.id, 10) - parseInt(a.id, 10));

    console.info(`[PixivService] 成功解析 ${novels.length} 部小说`);

    return {
      success: true,
      data: {
        novels,
        total:       allIds.length,
        currentPage: page,
        hasMore:     page * PAGE_SIZE < allIds.length,
        keyword:     ''
      }
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 搜索小说
  // ──────────────────────────────────────────────────────────────────────────

  async searchNovels(params: PixivSearchParams): Promise<ServiceResult<PixivSearchResult>> {
    const keyword = params.keyword;
    const page    = params.page    ?? 1;
    const order   = params.order   ?? PixivSortOrder.DATE_DESC;
    const mode    = params.mode    ?? PixivContentMode.ALL;
    const sMode   = params.searchMode ?? PixivSearchMode.TAG_ONLY;

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
      return { success: false, error: this.translatePixivError(resp.data.message) };
    }

    const body    = resp.data.body;
    const rawList = body?.novel?.data  ?? [];
    const total   = body?.novel?.total ?? 0;
    const novels: PixivNovel[] = rawList.map(
      (raw: RawPixivNovelItem): PixivNovel => parsePixivNovelFromRaw(raw)
    );

    return {
      success: true,
      data: { novels, total, currentPage: page, hasMore: page * 60 < total, keyword }
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 获取小说正文
  // ──────────────────────────────────────────────────────────────────────────

  async fetchNovelText(novelId: string): Promise<ServiceResult<string>> {
    if (!novelId) {
      return { success: false, error: '小说 ID 不能为空' };
    }

    const url  = `${AJAX_BASE}/novel/${novelId}`;
    const resp = await this.get<PixivAjaxResponse<NovelDetailBody>>(url, TIMEOUT_FETCH);

    if (!resp.success || !resp.data) {
      return { success: false, error: resp.error, code: resp.code };
    }
    if (resp.data.error) {
      return { success: false, error: this.translatePixivError(resp.data.message) };
    }

    const content = resp.data.body?.content ?? '';
    if (!content) {
      return { success: false, error: '正文内容为空，可能需要登录后访问' };
    }

    return { success: true, data: content };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 获取小说详情
  // ──────────────────────────────────────────────────────────────────────────

  async fetchNovelDetail(novelId: string): Promise<ServiceResult<PixivNovel>> {
    const url  = `${AJAX_BASE}/novel/${novelId}`;
    const resp = await this.get<PixivAjaxResponse<NovelDetailBody>>(url, TIMEOUT_FETCH);

    if (!resp.success || !resp.data) {
      return { success: false, error: resp.error, code: resp.code };
    }
    if (resp.data.error) {
      return { success: false, error: this.translatePixivError(resp.data.message) };
    }

    const b = resp.data.body;
    const novel: PixivNovel = {
      id:            b.id,
      title:         b.title,
      caption:       b.description  ?? '',
      author:        b.userName,
      authorId:      b.userId,
      coverUrl:      b.coverUrl     ?? '',
      tags:          (b.tags?.tags ?? []).map((t: TagItem): PixivTag => {
        const tag: PixivTag = {
          name:        t.tag,
          translation: t.translation?.zh ?? t.translation?.en ?? undefined
        };
        return tag;
      }),
      textLength:    b.wordCount    ?? 0,
      pageCount:     b.pageCount    ?? 1,
      createDate:    b.createDate   ?? '',
      updateDate:    b.uploadDate   ?? '',
      series: b.seriesNavData ? ((): PixivSeries => {
        const s: PixivSeries = {
          id:    String(b.seriesNavData!.seriesId),
          title: b.seriesNavData!.title,
          order: b.seriesNavData!.order
        };
        return s;
      })() : undefined,
      bookmarkCount: b.bookmarkCount ?? 0,
      viewCount:     b.viewCount     ?? 0,
      commentCount:  b.commentCount  ?? 0,
      cacheStatus:   CacheStatus.NOT_CACHED,
      fullText:      b.content       ?? undefined
    };

    return { success: true, data: novel };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 获取关注用户最新小说
  // ──────────────────────────────────────────────────────────────────────────

  async fetchFollowingNovels(page: number = 1): Promise<ServiceResult<PixivSearchResult>> {
    const url =
      `${AJAX_BASE}/follow_latest/novel` +
        `?mode=all` +
        `&p=${page}` +
        `&lang=zh`;

    const resp = await this.get<PixivAjaxResponse<FollowingNovelBody>>(url, TIMEOUT_SEARCH);

    if (!resp.success || !resp.data) {
      return { success: false, error: resp.error, code: resp.code };
    }
    if (resp.data.error) {
      return { success: false, error: this.translatePixivError(resp.data.message) };
    }

    const body    = resp.data.body;
    const rawList = body?.thumbnails?.novel ?? [];
    const total   = body?.page?.total       ?? 0;

    const novels: PixivNovel[] = rawList.map(
      (raw: RawPixivNovelItem): PixivNovel => parsePixivNovelFromRaw(raw)
    );

    return {
      success: true,
      data: { novels, total, currentPage: page, hasMore: page * 60 < total, keyword: '' }
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 工具方法
  // ──────────────────────────────────────────────────────────────────────────

  getNovelWebUrl(novelId: string): string {
    return `${BASE_URL}/novel/show.php?id=${novelId}`;
  }

  async checkLogin(): Promise<ServiceResult<boolean>> {
    if (!this.phpSessionId) {
      return { success: true, data: false, error: 'PHPSESSID 未填写' };
    }

    const url  = `${AJAX_BASE}/user/extra`;
    const resp = await this.get<PixivAjaxResponse<object>>(url, TIMEOUT_SEARCH);

    if (!resp.success) {
      if (resp.code === 401 || resp.code === 403) {
        return { success: true, data: false, error: 'Cookie 已失效' };
      }
      return { success: false, error: resp.error };
    }

    return { success: true, data: !(resp.data as PixivAjaxResponse<object>)?.error };
  }

  // ========================================
  // 私有：底层 HTTP 封装
  // ========================================

  private async get<T>(url: string, timeout: number): Promise<ServiceResult<T>> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method:         http.RequestMethod.GET,
        connectTimeout: timeout,
        readTimeout:    timeout,
        header: {
          'Cookie':          this.buildCookieHeader(),
          'User-Agent':      this.getUserAgent(),
          'Referer':         BASE_URL + '/',
          'Accept':          'application/json',
          'Accept-Language': 'zh-CN,zh;q=0.9,ja;q=0.8',
          'x-user-id':       this.getUserIdFromCookie()
        }
      });

      const code = response.responseCode;
      if (code === 401 || code === 403) {
        return { success: false, error: 'Cookie 已失效，请在设置中重新填入 PHPSESSID', code };
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
      return { success: false, error: this.parseNetworkError(err as object) };
    } finally {
      httpRequest.destroy();
    }
  }

  private async getWithReferer<T>(url: string, referer: string, timeout: number): Promise<ServiceResult<T>> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method:         http.RequestMethod.GET,
        connectTimeout: timeout,
        readTimeout:    timeout,
        header: {
          'Cookie':          this.buildCookieHeader(),
          'User-Agent':      this.getUserAgent(),
          'Referer':         referer,
          'Accept':          'application/json',
          'Accept-Language': 'zh-CN,zh;q=0.9,ja;q=0.8',
          'x-user-id':       this.getUserIdFromCookie()
        }
      });

      const code = response.responseCode;
      if (code === 401 || code === 403) {
        return { success: false, error: 'Cookie 已失效，请在设置中重新填入 PHPSESSID', code };
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
      return { success: false, error: this.parseNetworkError(err as object) };
    } finally {
      httpRequest.destroy();
    }
  }

  // ========================================
  // 私有：工具方法
  // ========================================

  private buildCookieHeader(): string {
    const base = 'GDPR_NOTICE_SEEN=1; p_ab_id=0; p_ab_id_2=0; p_ab_d_id=0;';
    if (this.phpSessionId) {
      return `${base} PHPSESSID=${this.phpSessionId};`;
    }
    return base;
  }

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

  private parseNetworkError(err: object): string {
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
// 节流工具
// ========================================

export class SearchThrottle {
  private lastSearchTime: number = 0;
  private readonly interval: number;

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

  remainingMs(): number {
    const elapsed = Date.now() - this.lastSearchTime;
    return Math.max(0, this.interval - elapsed);
  }
}

// ========================================
// 单例工厂
// ========================================

let _serviceInstance: PixivService | null = null;

export function getPixivService(): PixivService {
  const cookie = AppStorage.get<string>('pixivSessionId') ?? '';
  if (!_serviceInstance) {
    _serviceInstance = new PixivService(cookie);
  } else {
    _serviceInstance.updateSession(cookie);
  }
  return _serviceInstance;
}