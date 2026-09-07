import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

/** 仅清理旧版提醒；失败留待下次启动重试，不请求通知授权。 */
export async function retireLegacyReminders(context: common.Context): Promise<void> {
  try {
    const prefs = preferences.getPreferencesSync(context, { name: 'bill_settings' });
    if (prefs.getSync('reminders_retired_v1', false) === true) { return; }
    await reminderAgentManager.cancelAllReminders();
    const remaining = await reminderAgentManager.getValidReminders();
    if (remaining.length > 0) { throw new Error('Legacy reminders still registered'); }
    prefs.deleteSync('reminder_enabled');
    prefs.putSync('reminders_retired_v1', true);
    await prefs.flush();
    hilog.info(0x0000, 'BillReminderCleanup', 'Legacy reminders retired; remaining=0');
  } catch (e) {
    hilog.error(0x0000, 'BillReminderCleanup', 'Cleanup failed; retry next launch');
  }
}
