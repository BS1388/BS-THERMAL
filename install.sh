##########################################################
# BS THERMAL - Magisk module installer
# Thermal daemons/limits are torn down at runtime by service.sh;
# this module ships no system/vendor partition overlay.
##########################################################

SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=true
LATESTARTSERVICE=true

REPLACE="
"

# --- extract module payload ---
mkdir -p "$MODPATH"
unzip -o "$ZIPFILE" 'banner' -d "$MODPATH" >&2
unzip -o "$ZIPFILE" 'common/*' -d "$TMPDIR" >&2
unzip -o "$ZIPFILE" 'webroot/*' -d "$MODPATH" >&2
unzip -o "$ZIPFILE" 'system/*' -d "$MODPATH" >&2
unzip -o "$ZIPFILE" 'action.sh' -d "$MODPATH" >&2
cp -af "$TMPDIR/common/@Babak1388.png" "$MODPATH/@Babak1388.png" 2>/dev/null
cp -af "$TMPDIR/common/service.sh" "$MODPATH/service.sh" 2>/dev/null
cp -af "$TMPDIR/common/system.prop" "$MODPATH/system.prop" 2>/dev/null

# --- banner / device info ---
ui_print "================================================================"
ui_print "$(awk '{print}' "$MODPATH/banner")"
ui_print "================================================================"
sleep 1
ui_print "                               BS THERMAL"
sleep 0.1
ui_print "================================================================"
sleep 0.2
ui_print "                               Babak1388"
ui_print "================================================================"
sleep 1
ui_print "                                "
ui_print "▒▒▒▒ Device Info ▒▒▒▒"
ui_print "-------------------------------------------------"
ui_print "  DEVICE       : $(getprop ro.product.name)"
sleep 0.1
ui_print "  MODEL        : $(getprop ro.product.model)"
sleep 0.1
ui_print "  OPENGL       : $(getprop ro.opengles.version)"
sleep 0.1
ui_print "  SELINUX      : $(getenforce)"
sleep 0.1
ui_print "  KERNEL       : $(uname -r)"
sleep 0.1
ui_print "  PLATFORM     : $(getprop ro.board.platform)"
sleep 0.1
ui_print "  BUILD DATE   : $(getprop ro.system.build.date)"
sleep 0.2
ui_print "  ANDROID      : $(getprop ro.system.build.version.release) ($(uname -m))"
sleep 0.1
ui_print "  ROM          : $(getprop ro.build.flavor)"
sleep 0.1
ui_print "  DESCRIPTION  : $(getprop ro.build.description)"
sleep 0.1
ui_print "  FINGERPRINT  : $(getprop ro.build.fingerprint)"
sleep 0.1
ui_print "  SECURITY     : $(getprop ro.build.version.security_patch)"
ui_print "-------------------------------------------------"
sleep 0.2
ui_print "                                "
ui_print "▒▒▒▒ Starting installation ▒▒▒▒"
sleep 1

# --- permissions ---
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755

ui_print " "
ui_print "▒▒▒▒ Installation complete ▒▒▒▒"
ui_print " "

am start -a android.intent.action.VIEW -d https://t.me/Persian_Magisk >/dev/null 2>&1
