// entry/src/main/ets/utils/PreferencesUtil.ets

import dataPreferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';

const STORE_NAME = 'pixiv_user_prefs';   // 持久化文件名
const KEY_SESSION = 'pixivSessionId';    // Cookie key

let _prefsInstance: dataPreferences.Preferences | null = null;

/**
 * 初始化持久化存储（在 EntryAbility.onCreate 里调用一次）
 */
export async function initPreferences(ctx: common.UIAbilityContext): Promise<void> {
  try {
    _prefsInstance = await dataPreferences.getPreferences(ctx, STORE_NAME);
    console.info('[PreferencesUtil] 初始化成功');

    // ✅ 启动时把持久化的 Cookie 读出来，同步到 AppStorage，让全局可用
    const saved = await _prefsInstance.get(KEY_SESSION, '') as string;
    AppStorage.setOrCreate(KEY_SESSION, saved);
    console.info(`[PreferencesUtil] 已从磁盘恢复 PHPSESSID: ${saved ? saved.substring(0, 8) + '...' : '(空)'}`);
  } catch (e) {
    console.error('[PreferencesUtil] 初始化失败: ' + JSON.stringify(e));
  }
}

/**
 * 保存 PHPSESSID（写盘 + 同步 AppStorage）
 */
export async function saveSessionId(sessionId: string): Promise<void> {
  try {
    // 同步到内存（让当次运行立即生效）
    AppStorage.setOrCreate(KEY_SESSION, sessionId);

    // 写入磁盘（下次启动恢复用）
    if (_prefsInstance) {
      await _prefsInstance.put(KEY_SESSION, sessionId);
      await _prefsInstance.flush();  // ← 必须 flush 才真正落盘！
      console.info('[PreferencesUtil] PHPSESSID 已持久化到磁盘');
    } else {
      console.warn('[PreferencesUtil] Preferences 未初始化，仅写入 AppStorage');
    }
  } catch (e) {
    console.error('[PreferencesUtil] 保存失败: ' + JSON.stringify(e));
  }
}

/**
 * 读取 PHPSESSID
 */
export function getSessionId(): string {
  return AppStorage.get<string>(KEY_SESSION) ?? '';
}

/**
 * 清除 PHPSESSID（写盘 + 清 AppStorage）
 */
export async function clearSessionId(): Promise<void> {
  await saveSessionId('');
  console.info('[PreferencesUtil] PHPSESSID 已清除');
}