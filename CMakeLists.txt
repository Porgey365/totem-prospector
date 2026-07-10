# Out-of-tree code vendored in this config repo. Picked up by ZMK because a
# zephyr/module.yml exists at the repo root (build adds -DZMK_EXTRA_MODULES).
if(CONFIG_TOTEM_APDS_PROBE)
  zephyr_library()
  zephyr_library_sources(src/apds_probe.c)
endif()
