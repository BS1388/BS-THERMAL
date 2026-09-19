#!/system/bin/sh
# BS THERMAL - service.sh (cleaned)
# Runs once per boot and tears down thermal management:
# HAL services, kernel thermal zones, PPM/GPU limits, MSM/MTK thermal driver.
# NOTE: 125C MTK cutoff and install.sh copy-step intentionally left untouched (by request).
sleep 30

MODDIR=${0%/*}
AGGRESSIVE_MODE=1

# ---------------- generic helper ----------------
# usage: lock_val <value> <path1> [path2] ...
lock_val() {
    value="$1"
    shift
    for p in "$@"; do
        if [ -f "$p" ]; then
            chown root:root "$p" 2>/dev/null
            chmod 644 "$p" 2>/dev/null
            echo "$value" > "$p" 2>/dev/null
            chmod 444 "$p" 2>/dev/null
        fi
    done
}

# ---------------- stop thermal-named init services (covers HAL too) ----------------
stop_all_thermal_services() {
    for rc in $(find /system/etc/init /vendor/etc/init /odm/etc/init -type f 2>/dev/null); do
        grep -r "^service" "$rc" 2>/dev/null | awk '{print $2}'
    done | grep thermal | while IFS= read -r svc; do
        echo "Stopping $svc"
        stop "$svc" 2>/dev/null
    done
}

# ---------------- kernel thermal zones ----------------
disable_thermal_zones() {
    for zone in /sys/class/thermal/thermal_zone*; do
        [ -w "$zone/mode" ] && echo disabled > "$zone/mode" 2>/dev/null
        [ -w "$zone/policy" ] && echo userspace > "$zone/policy" 2>/dev/null
    done
    lock_val 0 /sys/class/thermal/thermal_zone0/thm_enable
    find /sys/devices/virtual/thermal -type f -exec chmod 000 {} + 2>/dev/null
}

# ---------------- GPU limits (gpufreq + Mali) ----------------
disable_gpu_limits() {
    if [ -f /proc/gpufreq/gpufreq_power_limited ]; then
        for setting in ignore_batt_oc ignore_batt_percent ignore_low_batt ignore_thermal_protect ignore_pbm_limited; do
            echo "$setting 1" > /proc/gpufreq/gpufreq_power_limited 2>/dev/null
        done
    fi
    if [ -f /proc/gpufreq/gpufreq_limit_table ]; then
        for i in 0 1 2 3 4 5 6 7 8; do
            echo "$i 0 0" > /proc/gpufreq/gpufreq_limit_table 2>/dev/null
        done
    fi
    for f in /sys/devices/*.mali/tmu /sys/devices/*.mali/throttling1 /sys/devices/*.mali/throttling2 \
             /sys/devices/*.mali/throttling3 /sys/devices/*.mali/throttling4 /sys/devices/*.mali/tripping; do
        [ -e "$f" ] && chmod 000 "$f" 2>/dev/null
    done
}

# ---------------- CPU max-frequency passthrough ----------------
set_cpu_max_freq() {
    [ -f /sys/devices/virtual/thermal/thermal_message/cpu_limits ] || return
    for cpu in 0 2 4 6 7; do
        maxfreq_path="/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq"
        [ -f "$maxfreq_path" ] || continue
        maxfreq=$(cat "$maxfreq_path")
        if [ -n "$maxfreq" ] && [ "$maxfreq" -gt 0 ] 2>/dev/null; then
            echo "cpu$cpu $maxfreq" > /sys/devices/virtual/thermal/thermal_message/cpu_limits 2>/dev/null
        fi
    done
}

# ---------------- PPM (MediaTek) policies ----------------
disable_ppm_limits() {
    if [ -d /proc/ppm ] && [ -f /proc/ppm/policy_status ]; then
        grep -E 'FORCE_LIMIT|PWR_THRO|THERMAL' /proc/ppm/policy_status 2>/dev/null \
            | awk -F'[][]' '{print $2}' | while read -r idx; do
                echo "$idx 0" > /proc/ppm/policy_status 2>/dev/null
            done
    fi
    if [ -f /proc/ppm/enabled ]; then
        echo 1 > /proc/ppm/enabled 2>/dev/null
        for i in 0 2 3 4 5 6 7 8; do
            echo "$i 0" > /proc/ppm/policy_status 2>/dev/null
        done
        echo "1 1" > /proc/ppm/policy_status 2>/dev/null
        echo "9 1" > /proc/ppm/policy_status 2>/dev/null
        echo "1 -1" > /proc/ppm/policy/hard_userlimit_max_cpu_freq 2>/dev/null
        echo "0 -1" > /proc/ppm/policy/hard_userlimit_max_cpu_freq 2>/dev/null
        echo "1 -1" > /proc/ppm/policy/hard_userlimit_min_cpu_freq 2>/dev/null
        echo "0 -1" > /proc/ppm/policy/hard_userlimit_min_cpu_freq 2>/dev/null
        echo "0 0" > /proc/ppm/policy/ut_fix_freq_idx 2>/dev/null
    fi
}

# ---------------- Qualcomm msm_thermal ----------------
disable_msm_thermal() {
    lock_val 0 /sys/kernel/msm_thermal/enabled /sys/class/kgsl/kgsl-3d0/throttling
    lock_val N /sys/module/msm_thermal/parameters/enabled
    lock_val 0 /sys/module/msm_thermal/core_control/enabled
    lock_val 0 /sys/module/msm_thermal/vdd_restriction/enabled
    lock_val "stop 1" /proc/mtk_batoc_throttling/battery_oc_protect_stop

    find /sys/ -name enabled 2>/dev/null | grep msm_thermal | while IFS= read -r f; do
        [ -r "$f" ] || continue
        case "$(cat "$f")" in
            Y) echo N > "$f" 2>/dev/null ;;
            1) echo 0 > "$f" 2>/dev/null ;;
        esac
    done
}

# ---------------- MediaTek thermal driver (125C cutoff kept as-is, per request) ----------------
disable_mtk_thermal_driver() {
    [ -f /proc/driver/thermal/tzcpu ] || return
    t_limit="125" # Celsius - unchanged
    no_cooler="0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler"
    for tz in tzcpu tzpmic tzbattery tzpa tzcharger tzwmt tzbts tzbtsnrpa tzbtspa; do
        [ -f "/proc/driver/thermal/$tz" ] && \
            lock_val "1 ${t_limit}000 0 mtktscpu-sysrst $no_cooler 200" "/proc/driver/thermal/$tz"
    done
    echo "Remove MediaTek's thermal driver limit"
}

disable_io_stats() {
    for queue in /sys/block/sd*/queue; do
        [ -w "$queue/iostats" ] && echo 0 > "$queue/iostats" 2>/dev/null
    done
}

disable_workqueue_power_saving() {
    for param in power_efficient disable_numa; do
        f="/sys/module/workqueue/parameters/$param"
        [ -f "$f" ] || continue
        chmod 0644 "$f" 2>/dev/null
        echo N > "$f" 2>/dev/null
        chmod 0444 "$f" 2>/dev/null
    done
}

# ---------------- freeze thermal pids / properties ----------------
freeze_thermal_pids() {
    [ "$AGGRESSIVE_MODE" -eq 1 ] || return
    for pid in $(pgrep thermal 2>/dev/null); do
        echo "Freeze $pid"
        kill -STOP "$pid" 2>/dev/null
    done
}

freeze_thermal_properties() {
    [ "$AGGRESSIVE_MODE" -eq 1 ] || return
    for prop in $(resetprop 2>/dev/null | grep 'thermal.*running' | awk -F '[][]' '{print $2}'); do
        resetprop "$prop" freezed 2>/dev/null
    done
}

stop logd

# ================= wait for boot before touching anything, then run once =================
while [ -z "$(getprop sys.boot_completed)" ]; do
    sleep 1
done
sleep 30

resetprop -n thermal.channel "@Persian_Magisk" 2>/dev/null

stop_all_thermal_services
disable_thermal_zones
disable_gpu_limits
set_cpu_max_freq
disable_ppm_limits
disable_msm_thermal
disable_mtk_thermal_driver
disable_io_stats
disable_workqueue_power_saving
freeze_thermal_pids
freeze_thermal_properties

cmd power set-mode 0 2>/dev/null
cmd power set-adaptive-power-saver-enabled false 2>/dev/null
cmd power set-fixed-performance-mode-enabled true 2>/dev/null
cmd thermalservice override-status 0 2>/dev/null

# ================= notification (unchanged logic) =================
test_file="/storage/emulated/0/Android/.PERMISSION_TEST"
true > "$test_file" 2>/dev/null
while [ ! -f "$test_file" ]; do
    true > "$test_file" 2>/dev/null
    sleep 1
done
rm -f "$test_file"

cp -af "$MODDIR/@Babak1388.png" "/storage/emulated/0/@Babak1388.png" 2>/dev/null
sleep 2
su -lp 2000 -c "cmd notification post \
  -t 'BS THERMAL' \
  -i file:///sdcard/@Babak1388.png \
  -I file:///sdcard/@Babak1388.png \
  'changes_done' \
  'WORKING'" > /dev/null 2>&1
sleep 3
rm -f /storage/emulated/0/@Babak1388.png

for zone in /sys/class/thermal/thermal_zone*/mode; do
  if [ "$(cat "$zone")" = "enabled" ]; then
       echo "disabled" > "$zone"
  elif [ "$(cat "$zone")" = "1" ]; then
       echo "0" > "$zone"
  fi
done > /dev/null 2>&1
echo 0 > /proc/sys/kernel/sched_boost
echo N > /sys/module/msm_thermal/parameters/enabled
echo 0 > /sys/module/msm_thermal/core_control/enabled
echo 0 > /sys/kernel/msm_thermal/enabled
for queue in /sys/block/sd*/queue; do
  echo "0" > "$queue/iostats"
done > /dev/null 2>&1
stop logd
stoped() {
for thermal in $(getprop | awk -F '[][]' '/thermal/ {print $2}'); do
  statusss=$(getprop $thermal)
  if [ "$statusss" = "running" ] || [ "$statusss" = "restarting" ]; then
    setprop $thermal stopped
  fi
done > /dev/null 2>&1
}
stoped
sleep 2
for lawang in $(getprop|grep thermal|cut -f1 -d]|cut -f2 -d[|grep -F init.svc.|sed 's/init.svc.//'); do
  stop $lawang
done > /dev/null 2>&1
for bro in $(getprop|grep thermal|cut -f1 -d]|cut -f2 -d[|grep -F init.svc.); do
  setprop $bro stopped
done > /dev/null 2>&1
for brooo in $(getprop|grep thermal|cut -f1 -d]|cut -f2 -d[|grep -F init.svc_); do
  setprop $brooo ""
done > /dev/null 2>&1
for i in $(getprop | grep 'ro.*thermal' | cut -d '[' -f2 | cut -d ']' -f1); do
  resetprop -n "$i" 0
done > /dev/null 2>&1
for a in $(getprop | grep 'ro.*thermal' | awk -F '[][]' '{print $2}'); do
  resetprop -n "$a" 0
done > /dev/null 2>&1
sleep 1
find /sys/devices/virtual/thermal -type f -exec chmod 000 {} +
echo '0' > /sys/class/kgsl/kgsl-3d0/throttling
echo '1' > /sys/class/kgsl/kgsl-3d0/force_clk_on
echo '1' > /sys/class/kgsl/kgsl-3d0/force_bus_on
echo '1' > /sys/class/kgsl/kgsl-3d0/force_rail_on
echo '1' > /sys/class/kgsl/kgsl-3d0/force_no_nap

#end