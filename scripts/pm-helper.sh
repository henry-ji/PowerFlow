#!/bin/bash
# powermetrics 实测守护进程：由 Power Flow 通过一次管理员授权安装为 LaunchDaemon（launchd 持有，开机自启）。
# 「实测」开关通过停止标记暂停/恢复采样，无需再次授权；卸载：Power Flow 右键菜单或 --pm-uninstall。
# 原始输出保留在 /tmp/pm-raw.txt 便于排查解析问题
PIDFILE=/tmp/powerflow-helper.pid
STOPFILE=/tmp/powerflow-helper.stop
if [[ $EUID -ne 0 ]]; then
  echo "powermetrics 需要 root 权限：请在 Power Flow 中开启「实测」，或以 sudo 运行：sudo $0" >&2
  exit 1
fi
CHILD=""
cleanup() {
  [[ -n "$CHILD" ]] && kill "$CHILD" 2>/dev/null
  rm -f "$PIDFILE"
}
trap cleanup EXIT
trap 'exit 0' TERM INT
echo $$ > "$PIDFILE"
while :; do
  if [[ -f "$STOPFILE" ]]; then
    sleep 1
    continue
  fi
  powermetrics --samplers cpu_power,gpu_power -i 2000 -n 1 > /tmp/pm-raw.txt 2>/dev/null &
  CHILD=$!
  wait "$CHILD"
  CHILD=""
  [[ -f "$STOPFILE" ]] && continue
  cpu=$(awk 'tolower($0) ~ /^cpu power:/ {print $3; exit}' /tmp/pm-raw.txt)
  gpu=$(awk 'tolower($0) ~ /^gpu power:/ {print $3; exit}' /tmp/pm-raw.txt)
  printf '{"cpu_mw":%s,"gpu_mw":%s}\n' "${cpu:-0}" "${gpu:-0}" > /tmp/powerflow-pm.json.tmp
  mv -f /tmp/powerflow-pm.json.tmp /tmp/powerflow-pm.json
done