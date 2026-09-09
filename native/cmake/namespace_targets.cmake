# Upstream packaging targets use the same global name in standalone projects.
# Namespace only these unused distribution targets for a combined source build.
set(path "${IMCODEC_SOURCE_DIR}/CMakeLists.txt")
file(READ "${path}" contents)
string(REGEX REPLACE "add_custom_target[ \t\r\n]*\\([ \t\r\n]*dist([ \t\r\n\\)])" "add_custom_target(${IMCODEC_PROJECT}_dist\\1" contents "${contents}")
file(WRITE "${path}" "${contents}")
