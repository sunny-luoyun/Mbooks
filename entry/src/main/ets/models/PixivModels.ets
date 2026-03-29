// entry/src/main/ets/models/PixivModels.ets

// ========================================
// 枚举：搜索源
// ========================================

export enum SearchSource {
  LOCAL = 'local',   // 本地书库（现有逻辑）
  PIXIV = 'pixiv',    // Pixiv 小说
  PIXIV_FOLLOWING  = 'pixiv_following' //  关注用户最新小说
}

// ========================================
// 枚举：小说缓存状态
// ========================================

export enum CacheStatus {
  NOT_CACHED = 'not_cached',   // 未缓存，仅有元数据
  CACHING    = 'caching',      // 缓存下载中
  CACHED     = 'cached',       // 已完整缓存正文
  CACHE_FAIL = 'cache_fail'    // 缓存失败
}

// ========================================
// 枚举：Pixiv 搜索排序方式
// ========================================

export enum PixivSortOrder {
  DATE_DESC  = 'date_d',   // 最新优先（默认）
  DATE_ASC   = 'date',     // 最早优先
  POPULAR    = 'popular_d' // 热度优先（需要Pixiv Premium）
}

// ========================================
// 枚举：Pixiv 搜索内容分级
// ========================================

export enum PixivContentMode {
  ALL    = 'all',    // 全部（含R18）
  SAFE   = 'safe',   // 全年龄
  R18    = 'r18'     // 仅R18
}

// ========================================
// 接口：Pixiv 小说标签
// ========================================

export interface PixivTag {
  name: string;           // 标签名（日文）
  translation?: string;   // 翻译（中文，Pixiv接口有时会返回）
}

// ========================================
// 接口：Pixiv 小说系列信息
// ========================================

export interface PixivSeries {
  id: string;     // 系列ID
  title: string;  // 系列名称
  order?: number; // 当前小说在系列中的序号
}

// ========================================
// 接口：Pixiv 小说核心数据模型
// ========================================

export interface PixivNovel {
  // --- 基础信息 ---
  id: string;               // 小说ID，唯一标识（对应数据库主键）
  title: string;            // 标题
  caption: string;          // 作者写的简介
  author: string;           // 作者名（displayName）
  authorId: string;         // 作者UID
  coverUrl: string;         // 封面图URL（pixiv的小说封面）

  // --- 内容信息 ---
  tags: PixivTag[];         // 标签列表
  textLength: number;       // 字数
  pageCount: number;        // 页数（Pixiv小说分页）
  createDate: string;       // 首次发布时间（ISO8601格式）
  updateDate: string;       // 最后更新时间

  // --- 系列信息（可选）---
  series?: PixivSeries;     // 所属系列，无系列则为 undefined

  // --- 统计数据 ---
  bookmarkCount: number;    // 收藏数
  viewCount: number;        // 阅读数
  commentCount: number;     // 评论数

  // --- 本地缓存状态（不来自API，本地维护）---
  cacheStatus: CacheStatus; // 缓存状态
  cachedAt?: string;        // 缓存完成时间（ISO8601格式）
  fullText?: string;        // 正文内容（仅 cacheStatus === CACHED 时有值）

  // --- 翻译相关字段（新增）---
  titleTranslated?: string;      // 翻译后的标题
  hasTitleTranslation?: boolean; // 是否有标题翻译
  fullTextTranslated?: string;   // 翻译后的全文
  hasFullTranslation?: boolean;  // 是否有全文翻译
  translationProgress?: number;  // 翻译进度 0-100
  translationStatus?: 'none' | 'in_progress' | 'completed' | 'failed'; // 翻译状态
}

// ========================================
// 接口：Pixiv 搜索请求参数
// ========================================

export interface PixivSearchParams {
  keyword: string;                    // 搜索关键词
  page: number;                       // 页码，从1开始
  order?: PixivSortOrder;             // 排序方式，默认 DATE_DESC
  mode?: PixivContentMode;            // 内容分级，默认 ALL
  searchMode?: PixivSearchMode;
  includeTranslationTags?: boolean;   // 是否匹配翻译后的标签
  searchType?: 'novel' | 'user';
}

// ========================================
// 接口：Pixiv 搜索结果（含分页信息）
// ========================================

export interface PixivSearchResult {
  novels: PixivNovel[];   // 本页小说列表
  total: number;          // 搜索命中总数
  currentPage: number;    // 当前页码
  hasMore: boolean;       // 是否有下一页
  keyword: string;        // 本次搜索的关键词（方便结果回显）
}

export interface PixivSeriesResult {
  seriesId: string;
  seriesTitle: string;
  seriesCaption?: string;
  authorId: string;
  authorName: string;
  novels: PixivNovel[];
  total: number;
  currentPage: number;
  hasMore: boolean;
}

// ========================================
// 新增：Pixiv 作者信息接口
// ========================================

export interface PixivAuthor {
  id: string;           // 作者UID
  name: string;         // 作者名
  account: string;      // 账号名
  avatarUrl: string;    // 头像URL
  isFollowed: boolean;  // 是否已关注
  novelCount?: number;  // 小说数量（搜索接口可能返回）
  illustCount?: number; // 插画数量
}
// ========================================
// 新增：作者搜索结果
// ========================================

export interface PixivAuthorSearchResult {
  authors: PixivAuthor[];  // 作者列表
  total: number;
  currentPage: number;
  hasMore: boolean;
  keyword: string;
}

// ========================================
// 接口：Pixiv 用户配置（存 AppStorage）
// ========================================

export interface PixivUserConfig {
  phpSessionId: string;   // 用户粘贴的 PHPSESSID，用于登录态
  contentMode: PixivContentMode;    // 内容分级偏好
  defaultSortOrder: PixivSortOrder; // 默认排序偏好
  autoCache: boolean;               // 是否点开后自动缓存正文
}

// ========================================
// 默认配置（新用户首次使用）
// ========================================

export const DEFAULT_PIXIV_CONFIG: PixivUserConfig = {
  phpSessionId: '',
  contentMode: PixivContentMode.ALL,
  defaultSortOrder: PixivSortOrder.DATE_DESC,
  autoCache: false
};
// ========================================
// 工具函数：从 API 原始 JSON 构造 PixivNovel
// ========================================
// Pixiv Ajax API 返回的系列信息原始结构（内部用，不导出）
export interface RawPixivSeriesInfo {
  id?: number;
  contentOrder?: number;
  viewableType?: number;
}

// Pixiv Ajax API 返回的单条小说原始结构（内部用，不导出）
export interface RawPixivNovelItem {
  id: string;
  title: string;
  comment: string;          // 对应 caption
  userName: string;
  userId: string;
  url: string;              // 封面图
  tags: string[];           // 纯字符串标签
  textCount: number;
  wordCount?: number;
  pageCount: number;
  createDate: string;
  updateDate: string;
  seriesId?: string;
  seriesTitle?: string;
  seriesOrder?: number;
  seriesContentOrder?: number;           // 方式1：thumbnails.novel 中的顺序
  series?: RawPixivSeriesInfo;           // 方式2：page.seriesContents 中的顺序
  bookmarkCount: number;
  viewCount: number;
  commentCount: number;
}

export function parsePixivNovelFromRaw(raw: RawPixivNovelItem): PixivNovel {

  let order = 0;
  if (raw.seriesContentOrder !== undefined) {
    order = raw.seriesContentOrder;
  } else if (raw.series?.contentOrder !== undefined) {
    order = raw.series.contentOrder;
  } else if (raw.seriesOrder !== undefined) {
    order = raw.seriesOrder;
  }
  return {
    id:           raw.id,
    title:        raw.title,
    caption:      raw.comment ?? '',
    author:       raw.userName,
    authorId:     raw.userId,
    coverUrl:     raw.url,
    tags:         (raw.tags ?? []).map((t: string) => ({ name: t } as PixivTag)),
    textLength: raw.textCount ?? raw.wordCount ?? 0,
    pageCount:    raw.pageCount ?? 1,
    createDate:   raw.createDate,
    updateDate:   raw.updateDate,
    series: raw.seriesId ? {
      id:    raw.seriesId,
      title: raw.seriesTitle ?? '',
      order: order
    } : undefined,
    bookmarkCount: raw.bookmarkCount ?? 0,
    viewCount:     raw.viewCount ?? 0,
    commentCount:  raw.commentCount ?? 0,
    // 本地状态初始化为未缓存
    cacheStatus: CacheStatus.NOT_CACHED
  };
}

// ========================================
// 工具函数：格式化字数显示
// ========================================

export function formatTextLength(len: number): string {
  if (len >= 10000) {
    return (len / 10000).toFixed(1) + '万字';
  }
  if (len >= 1000) {
    return (len / 1000).toFixed(1) + '千字';
  }
  return len + '字';
}

// ========================================
// 工具函数：格式化日期显示
// ========================================

export function formatPixivDate(isoDate: string): string {
  if (!isoDate) return '';
  // "2024-03-15T12:34:56+09:00" -> "2024/03/15"
  return isoDate.substring(0, 10).replace(/-/g, '/');
}

// 新增：搜索模式
export enum PixivSearchMode {
  TAG_ONLY    = 's_tag',       // 标签精确匹配（网站默认，推荐）
  TAG_FULL    = 's_tag_full',  // 标签完整词匹配
  TEXT        = 's_tc'         // 标题/说明文字模糊搜索
}

// ========================================
// 工具函数：判断小说是否可离线阅读
// ========================================

export function isReadableOffline(novel: PixivNovel): boolean {
  return novel.cacheStatus === CacheStatus.CACHED;  // 只看状态，不看内存fullText
}

// ========================================
// 工具函数：获取缓存状态的显示文字和颜色
// ========================================

export interface CacheStatusDisplay {
  label: string;
  color: string;
}

export function getCacheStatusDisplay(status: CacheStatus): CacheStatusDisplay {
  switch (status) {
    case CacheStatus.CACHED:
      return { label: '已缓存', color: '#52C41A' };
    case CacheStatus.CACHING:
      return { label: '缓存中', color: '#FAAD14' };
    case CacheStatus.CACHE_FAIL:
      return { label: '缓存失败', color: '#FF4D4F' };
    case CacheStatus.NOT_CACHED:
    default:
      return { label: '未缓存', color: '#999999' };
  }
}