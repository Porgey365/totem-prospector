/*
 * One-shot boot diagnostic: read the APDS9960's registers directly over I2C and
 * log them, independent of the stock driver (which aborts on the unexpected
 * chip id). Distinguishes a valid-but-unlisted chip id from a bad I2C read.
 *
 * The read is deferred a few seconds after boot so its output streams out over
 * live USB logging rather than being dropped from the small early-boot buffer.
 *
 * SPDX-License-Identifier: MIT
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/init.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(apds_probe, LOG_LEVEL_INF);

#define APDS_NODE DT_NODELABEL(apds9960)

static void apds_probe_work(struct k_work *work)
{
	const struct device *bus = DEVICE_DT_GET(DT_BUS(APDS_NODE));
	const uint16_t addr = DT_REG_ADDR(APDS_NODE);

	if (!device_is_ready(bus)) {
		LOG_ERR("APDS probe: I2C bus %s not ready",
			bus ? bus->name : "?");
		return;
	}

	LOG_INF("APDS probe: bus=%s addr=0x%02x", bus->name, addr);

	/* Read the ID register (0x92) several times to check for stability. */
	for (int i = 0; i < 5; i++) {
		uint8_t id = 0xff;
		int rc = i2c_reg_read_byte(bus, addr, 0x92, &id);

		LOG_INF("APDS probe: ID(0x92) read #%d -> rc=%d val=0x%02x",
			i, rc, id);
		k_msleep(30);
	}

	/* Dump the ENABLE/config/ID register window for a fingerprint. */
	for (uint8_t reg = 0x80; reg <= 0x9f; reg++) {
		uint8_t v = 0xff;
		int rc = i2c_reg_read_byte(bus, addr, reg, &v);

		LOG_INF("APDS probe: reg 0x%02x = 0x%02x (rc=%d)", reg, v, rc);
		k_msleep(10);
	}

	LOG_INF("APDS probe: done");
}

static K_WORK_DELAYABLE_DEFINE(apds_probe_dwork, apds_probe_work);

static int apds_probe_init(void)
{
	/* Defer ~8s so USB logging is attached and draining live by then. */
	k_work_schedule(&apds_probe_dwork, K_SECONDS(8));
	return 0;
}

SYS_INIT(apds_probe_init, APPLICATION, 90);
