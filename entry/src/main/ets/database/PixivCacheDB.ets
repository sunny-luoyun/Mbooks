// entry/src/main/ets/database/PixivCacheDB.ets

import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import {
  PixivNovel,
  PixivTag,
  PixivSeries,
  CacheStatus
} from '../models/PixivModels';

// ========================================
// 常量：数据库配置
// ========================================

const DB_NAME = 'pixiv_cache.db';
const TABLE_NOVELS = 'pixiv_novels';
const DB_VERSION = 1;

// ========================================
// 建表 SQL
// ========================================

const SQL_CREATE_NOVELS_TABLE = `
  CREATE TABLE IF NOT EXISTS ${TABLE_NOVELS} (
    id            TEXT    PRIMARY KEY,
    title         TEXT    NOT NULL,
    caption       TEXT    DEFAULT '',
    author        TEXT    DEFAULT '',
    author_id     TEXT    DEFAULT '',
    cover_url     TEXT    DEFAULT '',
    tags          TEXT    DEFAULT '[]',
    text_length   INTEGER DEFAULT 0,
    page_count    INTEGER DEFAULT 1,
    create_date   TEXT    DEFAULT '',
    update_date   TEXT    DEFAULT '',
    series_id     TEXT    DEFAULT '',
    series_title  TEXT    DEFAULT '',
    series_order  INTEGER DEFAULT 0,
    bookmark_count INTEGER DEFAULT 0,
    view_count    INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    cache_status  TEXT    DEFAULT 'not_cached',
    cached_at     TEXT    DEFAULT '',
    full_text     TEXT    DEFAULT '',
    title_translated   TEXT    DEFAULT '',
    has_title_translation INTEGER DEFAULT 0,
    full_text_translated TEXT  DEFAULT '',
    has_full_translation INTEGER DEFAULT 0,
    translation_status  TEXT    DEFAULT 'none',
    translation_progress INTEGER DEFAULT 0
  )
`;
// ========================================
// 列名常量（防止拼写错误）
// ========================================
interface ColumnMap {
  ID: string;
  TITLE: string;
  CAPTION: string;
  AUTHOR: string;
  AUTHOR_ID: string;
  COVER_URL: string;
  TAGS: string;
  TEXT_LENGTH: string;
  PAGE_COUNT: string;
  CREATE_DATE: string;
  UPDATE_DATE: string;
  SERIES_ID: string;
  SERIES_TITLE: string;
  SERIES_ORDER: string;
  BOOKMARK_COUNT: string;
  VIEW_COUNT: string;
  COMMENT_COUNT: string;
  CACHE_STATUS: string;
  CACHED_AT: string;
  FULL_TEXT: string;
  TITLE_TRANSLATED: string;
  HAS_TITLE_TRANSLATION: string;
  FULL_TEXT_TRANSLATED: string;
  HAS_FULL_TRANSLATION: string;
  TRANSLATION_STATUS: string;
  TRANSLATION_PROGRESS: string;
}

const COL: ColumnMap = {
  ID:             'id',
  TITLE:          'title',
  CAPTION:        'caption',
  AUTHOR:         'author',
  AUTHOR_ID:      'author_id',
  COVER_URL:      'cover_url',
  TAGS:           'tags',
  TEXT_LENGTH:    'text_length',
  PAGE_COUNT:     'page_count',
  CREATE_DATE:    'create_date',
  UPDATE_DATE:    'update_date',
  SERIES_ID:      'series_id',
  SERIES_TITLE:   'series_title',
  SERIES_ORDER:   'series_order',
  BOOKMARK_COUNT: 'bookmark_count',
  VIEW_COUNT:     'view_count',
  COMMENT_COUNT:  'comment_count',
  CACHE_STATUS:   'cache_status',
  CACHED_AT:      'cached_at',
  FULL_TEXT:      'full_text',
  TITLE_TRANSLATED:      'title_translated',
  HAS_TITLE_TRANSLATION: 'has_title_translation',
  FULL_TEXT_TRANSLATED:  'full_text_translated',
  HAS_FULL_TRANSLATION:  'has_full_translation',
  TRANSLATION_STATUS:    'translation_status',
  TRANSLATION_PROGRESS:  'translation_progress'
};

// 所有列（查询时用，避免 SELECT * 的隐患）
const ALL_COLUMNS: string[] = Object.values(COL);

// ========================================
// 核心类
// ========================================

export class PixivCacheDB {
  private rdbStore: relationalStore.RdbStore | null = null;
  private initialized: boolean = false;

  // ----------------------------------------
  // 初始化（在 aboutToAppear 里调用一次）
  // ----------------------------------------

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.initialized) return;

    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };

    try {
      this.rdbStore = await relationalStore.getRdbStore(ctx, config);
      const version: number = this.rdbStore.version;

      if (version === 0) {
        // 全新数据库：直接建包含所有字段的完整表
        await this.rdbStore.executeSql(SQL_CREATE_NOVELS_TABLE);
        this.rdbStore.version = DB_VERSION;
      } else if (version < DB_VERSION) {
        // 旧库升级：只做 ALTER TABLE（不重建表）
        await this.upgradeDatabase(version, DB_VERSION);
      }
      // version === DB_VERSION：无需任何操作

      this.initialized = true;
      console.info(`[PixivCacheDB] 初始化成功，数据库版本: v${DB_VERSION}`);
    } catch (err) {
      console.error(`[PixivCacheDB] 初始化失败: ${JSON.stringify(err)}`);
    }
  }

  private async upgradeDatabase(oldVersion: number, newVersion: number): Promise<void> {
    console.info(`[PixivCacheDB] 升级数据库: v${oldVersion} -> v${newVersion}`);

    if (oldVersion < 1) {
      const alterQueries = [
        `ALTER TABLE ${TABLE_NOVELS} ADD COLUMN title_translated TEXT DEFAULT '';`,
        `ALTER TABLE ${TABLE_NOVELS} ADD COLUMN has_title_translation INTEGER DEFAULT 0;`,
        `ALTER TABLE ${TABLE_NOVELS} ADD COLUMN full_text_translated TEXT DEFAULT '';`,
        `ALTER TABLE ${TABLE_NOVELS} ADD COLUMN has_full_translation INTEGER DEFAULT 0;`,
        `ALTER TABLE ${TABLE_NOVELS} ADD COLUMN translation_status TEXT DEFAULT 'none';`,
        `ALTER TABLE ${TABLE_NOVELS} ADD COLUMN translation_progress INTEGER DEFAULT 0;`
      ];

      for (const query of alterQueries) {
        try {
          await this.rdbStore!.executeSql(query);
        } catch (e) {
          // errno 25 = 列已存在，忽略（幂等）
          console.warn(`[PixivCacheDB] ALTER TABLE 跳过（列可能已存在）: ${JSON.stringify(e)}`);
        }
      }
    }

    this.rdbStore!.version = newVersion;
  }


  // 安全检查：所有操作前确认 DB 已就绪
  private checkReady(): boolean {
    if (!this.initialized || !this.rdbStore) {
      console.warn('[PixivCacheDB] 数据库尚未初始化，请先调用 init()');
      return false;
    }
    return true;
  }

  // ========================================
  // 写入操作
  // ========================================

  /**
   * 保存/更新小说元数据（搜索结果落库）
   * 使用 ON_CONFLICT_REPLACE 策略：ID 相同则更新，不存在则插入
   * 注意：不会覆盖已有的 full_text 和 cache_status
   */
  async saveNovelMeta(novel: PixivNovel): Promise<void> {
    if (!this.checkReady()) return;

    // 先检查是否已有缓存，避免覆盖 full_text
    const existing = await this.getNovelById(novel.id);
    const keepCacheStatus = existing?.cacheStatus ?? CacheStatus.NOT_CACHED;
    const keepFullText    = existing?.fullText    ?? '';
    const keepCachedAt    = existing?.cachedAt    ?? '';
    const values: relationalStore.ValuesBucket = {
      'id':             novel.id,
      'title':          novel.title,
      'caption':        novel.caption,
      'author':         novel.author,
      'author_id':      novel.authorId,
      'cover_url':      novel.coverUrl,
      'tags':           JSON.stringify(novel.tags),
      'text_length':    novel.textLength,
      'page_count':     novel.pageCount,
      'create_date':    novel.createDate,
      'update_date':    novel.updateDate,
      'series_id':      novel.series?.id    ?? '',
      'series_title':   novel.series?.title ?? '',
      'series_order':   novel.series?.order ?? 0,
      'bookmark_count': novel.bookmarkCount,
      'view_count':     novel.viewCount,
      'comment_count':  novel.commentCount,
      // 保留已有缓存状态，不因刷新元数据而重置
      'cache_status':   keepCacheStatus,
      'cached_at':      keepCachedAt,
      'full_text':      keepFullText,
      'title_translated':      novel.titleTranslated ?? '',
      'has_title_translation': novel.hasTitleTranslation ? 1 : 0,
      'full_text_translated':  novel.fullTextTranslated ?? '',
      'has_full_translation':  novel.hasFullTranslation ? 1 : 0,
      'translation_status':    novel.translationStatus ?? 'none',
      'translation_progress':  novel.translationProgress ?? 0
    };

    try {
      await this.rdbStore!.insert(
        TABLE_NOVELS,
        values,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );
    } catch (err) {
      console.error(`[PixivCacheDB] saveNovelMeta 失败 id=${novel.id}: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 批量保存元数据（搜索结果整页落库）
   * 使用事务保证原子性，比逐条插入快很多
   */
  async saveNovelMetaBatch(novels: PixivNovel[]): Promise<void> {
    if (!this.checkReady() || novels.length === 0) return;

    try {
      await this.rdbStore!.beginTransaction();
      for (const novel of novels) {
        await this.saveNovelMeta(novel);
      }
      await this.rdbStore!.commit();
      console.info(`[PixivCacheDB] 批量写入 ${novels.length} 条元数据`);
    } catch (err) {
      await this.rdbStore!.rollBack();
      console.error(`[PixivCacheDB] 批量写入失败，已回滚: ${JSON.stringify(err)}`);
    }
  }

  // 新增：保存翻译后的标题
  async saveTitleTranslation(novelId: string, translatedTitle: string): Promise<void> {
    await this.updateCacheFields(novelId, {
      'title_translated': translatedTitle,
      'has_title_translation': 1
    });
  }

  // 新增：保存翻译后的全文
  async saveFullTextTranslation(novelId: string, translatedText: string): Promise<void> {
    await this.updateCacheFields(novelId, {
      'full_text_translated': translatedText,
      'has_full_translation': 1,
      'translation_status': 'completed',
      'translation_progress': 100
    });
  }

  // 新增：更新翻译进度
  async updateTranslationProgress(novelId: string, progress: number, status: string): Promise<void> {
    await this.updateCacheFields(novelId, {
      'translation_progress': progress,
      'translation_status': status
    });
  }


  /**
   * 标记缓存开始（防止重复点击缓存按钮）
   */
  async markCaching(novelId: string): Promise<void> {
    await this.updateCacheFields(novelId, {
      'cache_status': CacheStatus.CACHING
    });
  }

  /**
   * 写入正文缓存（缓存完成后调用）
   */
  async saveFullText(novelId: string, fullText: string): Promise<void> {
    if (!this.checkReady()) return;
    if (!fullText || fullText.length === 0) {
      await this.markCacheFail(novelId);
      return;
    }
    const success = await this.updateCacheFields(novelId, {
      'full_text':    fullText,
      'cache_status': CacheStatus.CACHED,
      'cached_at':    new Date().toISOString()
    });
    if (success) {
      console.info(`[PixivCacheDB] saveFullText 成功 id=${novelId}，长度=${fullText.length}`);
    } else {
      console.error(`[PixivCacheDB] saveFullText 失败 id=${novelId}（记录不存在）`);
    }
  }

  /**
   * 标记缓存失败
   */
  async markCacheFail(novelId: string): Promise<void> {
    await this.updateCacheFields(novelId, {
      'cache_status': CacheStatus.CACHE_FAIL
    });
  }

  /**
   * 删除单条缓存（释放空间）
   */
  async deleteCachedText(novelId: string): Promise<void> {
    await this.updateCacheFields(novelId, {
      'full_text':    '',
      'cache_status': CacheStatus.NOT_CACHED,
      'cached_at':    ''
    });
    console.info(`[PixivCacheDB] 已删除正文缓存 id=${novelId}`);
  }

  /**
   * 删除整条记录（从书库移除）
   */
  async deleteNovel(novelId: string): Promise<void> {
    if (!this.checkReady()) return;
    const predicates = new relationalStore.RdbPredicates(TABLE_NOVELS);
    predicates.equalTo(COL.ID, novelId);
    try {
      await this.rdbStore!.delete(predicates);
    } catch (err) {
      console.error(`[PixivCacheDB] deleteNovel 失败 id=${novelId}: ${JSON.stringify(err)}`);
    }
  }

  // ========================================
  // 读取操作
  // ========================================

  /**
   * 按 ID 查单条（含正文）
   */
  async getNovelById(novelId: string): Promise<PixivNovel | null> {
    if (!this.checkReady()) return null;
    const predicates = new relationalStore.RdbPredicates(TABLE_NOVELS);
    predicates.equalTo(COL.ID, novelId);
    try {
      const result = await this.rdbStore!.query(predicates, ALL_COLUMNS);
      const novels = this.resultSetToNovels(result);
      return novels.length > 0 ? novels[0] : null;
    } catch (err) {
      console.error(`[PixivCacheDB] getNovelById 失败: ${JSON.stringify(err)}`);
      return null;
    }
  }

  /**
   * 只取正文（阅读时调用，避免把大字段全部加载到内存）
   */
  async getFullText(novelId: string): Promise<string | null> {
    if (!this.checkReady()) return null;
    const predicates = new relationalStore.RdbPredicates(TABLE_NOVELS);
    predicates.equalTo(COL.ID, novelId)
      .and()
      .equalTo(COL.CACHE_STATUS, CacheStatus.CACHED);
    try {
      const result = await this.rdbStore!.query(predicates, [COL.FULL_TEXT]);
      if (result.rowCount > 0) {
        result.goToFirstRow();
        const text = result.getString(result.getColumnIndex(COL.FULL_TEXT));
        result.close();
        console.info(`[PixivCacheDB] getFullText 成功 id=${novelId}，长度=${text?.length ?? 0}`);
        return text || null;
      }
      result.close();
      console.warn(`[PixivCacheDB] getFullText 未找到 id=${novelId} 或状态不为 cached`);
      return null;
    } catch (err) {
      console.error(`[PixivCacheDB] getFullText 失败: ${JSON.stringify(err)}`);
      return null;
    }
  }

  /**
   * 搜索本地缓存（关键词匹配标题/作者/标签）
   * 仅返回已完整缓存的小说（离线可读）
   */
  async searchCachedNovels(keyword: string): Promise<PixivNovel[]> {
    if (!this.checkReady()) return [];
    const predicates = new relationalStore.RdbPredicates(TABLE_NOVELS);

    if (keyword.trim().length > 0) {
      predicates.contains(COL.TITLE, keyword)
        .or()
        .contains(COL.AUTHOR, keyword)
        .or()
        .contains(COL.TAGS, keyword)  // tags 是 JSON 字符串，模糊匹配标签名有效
        .or()
        .contains(COL.CAPTION, keyword);
    }
    // 只返回有正文缓存的
    predicates.and().equalTo(COL.CACHE_STATUS, CacheStatus.CACHED);
    predicates.orderByDesc(COL.CACHED_AT);

    try {
      // 搜索时不加载 full_text，节省内存
      const cols = ALL_COLUMNS.filter(c => c !== COL.FULL_TEXT);
      const result = await this.rdbStore!.query(predicates, cols);
      return this.resultSetToNovels(result);
    } catch (err) {
      console.error(`[PixivCacheDB] searchCachedNovels 失败: ${JSON.stringify(err)}`);
      return [];
    }
  }

  /**
   * 获取所有元数据（不含正文），用于"我的缓存"列表页
   */
  async getAllCachedNovels(): Promise<PixivNovel[]> {
    if (!this.checkReady()) return [];
    const predicates = new relationalStore.RdbPredicates(TABLE_NOVELS);
    predicates.equalTo(COL.CACHE_STATUS, CacheStatus.CACHED)
      .orderByDesc(COL.CACHED_AT);
    try {
      const cols = ALL_COLUMNS.filter(c => c !== COL.FULL_TEXT);
      const result = await this.rdbStore!.query(predicates, cols);
      return this.resultSetToNovels(result);
    } catch (err) {
      console.error(`[PixivCacheDB] getAllCachedNovels 失败: ${JSON.stringify(err)}`);
      return [];
    }
  }

  /**
   * 查询指定搜索词的上次搜索结果元数据（全部，含未缓存）
   * 用于无网络时展示上次搜索结果
   */
  async getMetaByKeyword(keyword: string): Promise<PixivNovel[]> {
    if (!this.checkReady()) return [];
    const predicates = new relationalStore.RdbPredicates(TABLE_NOVELS);
    predicates.contains(COL.TITLE, keyword)
      .or()
      .contains(COL.AUTHOR, keyword)
      .or()
      .contains(COL.TAGS, keyword)
      .or()
      .contains(COL.CAPTION, keyword);
    predicates.orderByDesc(COL.CREATE_DATE);
    try {
      const cols = ALL_COLUMNS.filter(c => c !== COL.FULL_TEXT);
      const result = await this.rdbStore!.query(predicates, cols);
      return this.resultSetToNovels(result);
    } catch (err) {
      console.error(`[PixivCacheDB] getMetaByKeyword 失败: ${JSON.stringify(err)}`);
      return [];
    }
  }

  /**
   * 获取缓存统计信息（设置页展示用）
   */
  async getCacheStats(): Promise<CacheStats> {
    if (!this.checkReady()) {
      return { totalNovels: 0, cachedNovels: 0, totalChars: 0 };
    }
    try {
      // 总条数
      const allPredicates = new relationalStore.RdbPredicates(TABLE_NOVELS);
      const allResult = await this.rdbStore!.query(allPredicates, [COL.ID]);
      const totalNovels = allResult.rowCount;
      allResult.close();

      // 已缓存条数 + 总字数
      const cachedPredicates = new relationalStore.RdbPredicates(TABLE_NOVELS);
      cachedPredicates.equalTo(COL.CACHE_STATUS, CacheStatus.CACHED);
      const cachedResult = await this.rdbStore!.query(
        cachedPredicates, [COL.ID, COL.TEXT_LENGTH]
      );

      let totalChars = 0;
      const cachedNovels = cachedResult.rowCount;
      while (cachedResult.goToNextRow()) {
        totalChars += cachedResult.getLong(
          cachedResult.getColumnIndex(COL.TEXT_LENGTH)
        );
      }
      cachedResult.close();

      return { totalNovels, cachedNovels, totalChars };
    } catch (err) {
      console.error(`[PixivCacheDB] getCacheStats 失败: ${JSON.stringify(err)}`);
      return { totalNovels: 0, cachedNovels: 0, totalChars: 0 };
    }
  }

  /**
   * 清空全部缓存（用户主动触发）
   */
  async clearAllCache(): Promise<void> {
    if (!this.checkReady()) return;
    try {
      // 只清 full_text，保留元数据（下次搜索不需要重新联网）
      await this.rdbStore!.executeSql(
        `UPDATE ${TABLE_NOVELS}
         SET ${COL.FULL_TEXT}    = '',
             ${COL.CACHE_STATUS} = '${CacheStatus.NOT_CACHED}',
             ${COL.CACHED_AT}    = ''`
      );
      console.info('[PixivCacheDB] 全部缓存已清除');
    } catch (err) {
      console.error(`[PixivCacheDB] clearAllCache 失败: ${JSON.stringify(err)}`);
    }
  }

  // ========================================
  // 私有工具方法
  // ========================================

  /**
   * 通用字段更新（减少重复的 predicates 构造）
   */
  private async updateCacheFields(
    novelId: string,
    fields: relationalStore.ValuesBucket
  ): Promise<boolean> {
    if (!this.checkReady()) return false;
    const predicates = new relationalStore.RdbPredicates(TABLE_NOVELS);
    predicates.equalTo(COL.ID, novelId);
    try {
      const rows = await this.rdbStore!.update(fields, predicates);
      if (rows > 0) {
        return true;
      } else {
        console.warn(`[PixivCacheDB] updateCacheFields: 未找到id=${novelId}的记录`);
        // 可选：尝试插入一条只有 id 的记录（但需要其他字段默认值）
        // 此处先记录警告，由调用方保证记录存在（已通过 saveNovelMeta 确保）
        return false;
      }
    } catch (err) {
      console.error(`[PixivCacheDB] updateCacheFields 失败 id=${novelId}: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * ResultSet → PixivNovel[]
   * 统一出口，避免每个查询方法都写一遍解析逻辑
   */
  private resultSetToNovels(result: relationalStore.ResultSet): PixivNovel[] {
    const novels: PixivNovel[] = [];
    try {
      while (result.goToNextRow()) {
        const tagsRaw = result.getString(result.getColumnIndex(COL.TAGS));
        let tags: PixivTag[] = [];
        try {
          tags = JSON.parse(tagsRaw || '[]');
        } catch {
          tags = [];
        }

        const seriesId    = result.getString(result.getColumnIndex(COL.SERIES_ID));
        const seriesTitle = result.getString(result.getColumnIndex(COL.SERIES_TITLE));
        const seriesOrder = result.getLong(result.getColumnIndex(COL.SERIES_ORDER));
        const series: PixivSeries | undefined = seriesId
          ? { id: seriesId, title: seriesTitle, order: seriesOrder }
          : undefined;

        // full_text 可能不在查询列中（搜索列表时不查正文）
        let fullText: string | undefined = undefined;
        try {
          const ftIdx = result.getColumnIndex(COL.FULL_TEXT);
          if (ftIdx >= 0) {
            const ft = result.getString(ftIdx);
            fullText = ft || undefined;
          }
        } catch {
          // 列不存在，忽略
        }

        const cacheStatusRaw = result.getString(
          result.getColumnIndex(COL.CACHE_STATUS)
        ) as CacheStatus;

        novels.push({
          id:            result.getString(result.getColumnIndex(COL.ID)),
          title:         result.getString(result.getColumnIndex(COL.TITLE)),
          caption:       result.getString(result.getColumnIndex(COL.CAPTION)),
          author:        result.getString(result.getColumnIndex(COL.AUTHOR)),
          authorId:      result.getString(result.getColumnIndex(COL.AUTHOR_ID)),
          coverUrl:      result.getString(result.getColumnIndex(COL.COVER_URL)),
          tags,
          textLength:    result.getLong(result.getColumnIndex(COL.TEXT_LENGTH)),
          pageCount:     result.getLong(result.getColumnIndex(COL.PAGE_COUNT)),
          createDate:    result.getString(result.getColumnIndex(COL.CREATE_DATE)),
          updateDate:    result.getString(result.getColumnIndex(COL.UPDATE_DATE)),
          series,
          bookmarkCount: result.getLong(result.getColumnIndex(COL.BOOKMARK_COUNT)),
          viewCount:     result.getLong(result.getColumnIndex(COL.VIEW_COUNT)),
          commentCount:  result.getLong(result.getColumnIndex(COL.COMMENT_COUNT)),
          cacheStatus:   cacheStatusRaw || CacheStatus.NOT_CACHED,
          cachedAt:      result.getString(result.getColumnIndex(COL.CACHED_AT)) || undefined,
          fullText,
          titleTranslated:     result.getString(result.getColumnIndex(COL.TITLE_TRANSLATED))     || undefined,
          hasTitleTranslation: result.getLong(result.getColumnIndex(COL.HAS_TITLE_TRANSLATION))  === 1,
          fullTextTranslated:  result.getString(result.getColumnIndex(COL.FULL_TEXT_TRANSLATED))  || undefined,
          hasFullTranslation:  result.getLong(result.getColumnIndex(COL.HAS_FULL_TRANSLATION))   === 1,
          translationStatus:   (result.getString(result.getColumnIndex(COL.TRANSLATION_STATUS))  || 'none') as 'none' | 'in_progress' | 'completed' | 'failed',
          translationProgress: result.getLong(result.getColumnIndex(COL.TRANSLATION_PROGRESS))   ?? 0,
        });
      }
    } finally {
      result.close(); // 必须关闭，防止游标泄漏
    }
    return novels;
  }
}

// ========================================
// 缓存统计数据结构（设置页用）
// ========================================

export interface CacheStats {
  totalNovels: number;  // 库里总条数（含未缓存元数据）
  cachedNovels: number; // 已完整缓存正文的条数
  totalChars: number;   // 缓存正文总字数（估算占用空间用）
}

// ========================================
// 单例导出（全局共享同一个 DB 实例）
// ========================================

export const pixivCacheDB = new PixivCacheDB();