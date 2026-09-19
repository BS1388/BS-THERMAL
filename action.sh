#CEK THERMAL
echo "============== CPU governor =============="
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor   
echo "============== grep THERMAL =============="
getprop | grep thermal
echo "============== THERMAL zone  =============="
for tz in /sys/class/thermal/thermal_zone*; do
  [ -f "$tz/temp" ] || continue
  type=$(cat "$tz/type" 2>/dev/null)
  temp=$(cat "$tz/temp" 2>/dev/null)
  echo "$(basename "$tz") ($type): $((temp/1000))°C"
  done
#@Persian_Magisk (telegram)
