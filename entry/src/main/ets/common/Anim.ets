/**
 * 轻量数值补间（easeOutCubic），用于数字滚动和图表生长动画。
 * 返回 timer id，调用方负责在新动画启动前 clearInterval 取消上一次。
 */
export function tween(from: number, to: number, duration: number, onUpdate: (v: number) => void): number {
  const start = Date.now();
  const timer = setInterval(() => {
    const t = Math.min((Date.now() - start) / duration, 1);
    const e = 1 - Math.pow(1 - t, 3);
    onUpdate(from + (to - from) * e);
    if (t >= 1) {
      clearInterval(timer);
    }
  }, 16);
  return timer;
}
