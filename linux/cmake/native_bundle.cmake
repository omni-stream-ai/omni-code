# Prebuilt plugins need their own library search paths on Nix. The development
# shell supplies this tool, but a later plain flutter run must retain it.
if(NOT "$ENV{OMNI_CODE_LINUX_BUNDLE_PREPARER}" STREQUAL "")
  set(OMNI_CODE_LINUX_BUNDLE_PREPARER
    "$ENV{OMNI_CODE_LINUX_BUNDLE_PREPARER}" CACHE FILEPATH
    "Native Linux bundle dependency fixer" FORCE)
endif()
if(OMNI_CODE_LINUX_BUNDLE_PREPARER AND
   NOT EXISTS "${OMNI_CODE_LINUX_BUNDLE_PREPARER}")
  unset(OMNI_CODE_LINUX_BUNDLE_PREPARER CACHE)
endif()
find_program(OMNI_CODE_LINUX_BUNDLE_PREPARER
  NAMES omni-code-prepare-linux-bundle)

# A fresh build outside the development shell has no cached tool. Resolve the
# same pinned helper through the flake instead of silently shipping broken ELFs.
if(NOT OMNI_CODE_LINUX_BUNDLE_PREPARER AND
   (EXISTS "/etc/NIXOS" OR CMAKE_CXX_COMPILER MATCHES "^/nix/store/"))
  find_program(OMNI_NIX_EXECUTABLE NAMES nix)
  if(NOT OMNI_NIX_EXECUTABLE)
    message(FATAL_ERROR "omni_code: nix is required to resolve native runtime libraries")
  endif()
  get_filename_component(_omni_project_dir "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
  message(STATUS "omni_code: resolving the Nix native bundle dependency fixer")
  execute_process(
    COMMAND "${OMNI_NIX_EXECUTABLE}" build --no-link --print-out-paths
            --no-write-lock-file "${_omni_project_dir}#linux-bundle-preparer"
    RESULT_VARIABLE _omni_resolve_result
    OUTPUT_VARIABLE _omni_preparer_package
    ERROR_VARIABLE _omni_resolve_error
    OUTPUT_STRIP_TRAILING_WHITESPACE
    TIMEOUT 180
  )
  if(NOT _omni_resolve_result EQUAL 0 OR
     NOT EXISTS "${_omni_preparer_package}/bin/omni-code-prepare-linux-bundle")
    message(FATAL_ERROR "omni_code: failed to resolve native bundle dependency fixer: ${_omni_resolve_error}")
  endif()
  set(OMNI_CODE_LINUX_BUNDLE_PREPARER
    "${_omni_preparer_package}/bin/omni-code-prepare-linux-bundle" CACHE FILEPATH
    "Native Linux bundle dependency fixer" FORCE)
endif()

if(OMNI_CODE_LINUX_BUNDLE_PREPARER)
  install(CODE "
    execute_process(
      COMMAND \"${OMNI_CODE_LINUX_BUNDLE_PREPARER}\"
              \"${CMAKE_INSTALL_PREFIX}\"
      RESULT_VARIABLE _omni_prepare_result
    )
    if(NOT _omni_prepare_result EQUAL 0)
      message(FATAL_ERROR \"omni_code: native runtime dependencies are incomplete\")
    endif()
  " COMPONENT Runtime)
endif()
