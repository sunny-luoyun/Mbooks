// entry/src/main/ets/models/SettingsModels.ets

// ==================== 设置相关接口 ====================

// 关注作者配置
export interface WatchedAuthor {
  name: string;
  addTime: number;
  notifyOnUpdate: boolean;  // 是否推送通知
}

// 关注书籍配置
export interface WatchedBook {
  threadId: string;
  title: string;
  addTime: number;
  notifyOnUpdate: boolean;
  autoDownload: boolean;    // 自动下载更新
}

// 爬取参数配置
export interface CrawlerConfig {
  maxPagesPerRun: number;      // 单次最大页数 (1-10)
  stopAfterOldPages: number;   // 连续旧页停止数 (1-5)
  requestDelay: number;        // 请求间隔ms (500-3000)
  enableBreakpoint: boolean;   // 启用断点续爬
  autoCheckOnStartup: boolean; // 启动时自动检查
  checkIntervalHours: number;  // 后台检查间隔 (0=不自动)
}

// 通知设置
export interface NotificationConfig {
  enablePush: boolean;
  notifyNewThread: boolean;
  notifyUpdate: boolean;
  notifyWatchedOnly: boolean;  // 仅通知关注内容
}

// UI配置
export interface UIConfig {
  theme: 'light' | 'dark' | 'auto';
  fontSize: number;
  lineSpacing: number;
}

// 应用设置总接口
export interface AppSettings {
  version: number;             // 设置版本号，用于迁移
  authors: WatchedAuthor[];
  books: WatchedBook[];
  crawler: CrawlerConfig;
  notification: NotificationConfig;
  ui: UIConfig;
}

// ==================== 帖子/爬取相关接口 ====================

// 帖子项接口
export interface ThreadItem {
  threadId: string;
  title: string;
  author: string;
  lastTime: string;
  lastPid: string;
  prevLastPid?: string;
  isNew: boolean;
  isUpdated: boolean;
  tags: string[];
  createTime?: string;
  prevLastTime?: string;
}

// 下载结果接口
export interface DownloadResult {
  content: string;
  newIds: string[];
  author: string;
}

// 同步结果接口
export interface SyncResult {
  newThreads: ThreadItem[];
  updatedThreads: ThreadItem[];
  hasMore: boolean;
  resumeOffset: number;
}
// 带关注标记的帖子（扩展类型）
export interface ThreadItemWithMarks extends ThreadItem {
  watchMarks: string;
}