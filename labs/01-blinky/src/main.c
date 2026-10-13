/*
 * OpCode Labs - Zephyr training
 * Lab 01: toggle the board LED from one dedicated thread.
 *
 * The LED comes from the devicetree alias "led0", so the same code runs on:
 *   stm32f4_disco   (STM32F407 Discovery, green LED LD4 / PD12)
 *   nucleo_f446re   (green LED LD2 / PA5)
 *   nucleo_f429zi   (green LED LD1 / PB0)
 *   nucleo_g474re   (green LED LD2 / PA5)
 */
#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/sys/printk.h>

#define BLINK_PERIOD_MS   500
#define BLINK_STACK_SIZE  1024
#define BLINK_PRIORITY    5

static const struct gpio_dt_spec led = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);

static void blink_thread(void *p1, void *p2, void *p3)
{
	ARG_UNUSED(p1);
	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	if (!gpio_is_ready_dt(&led)) {
		printk("LED device %s not ready\n", led.port->name);
		return;
	}

	if (gpio_pin_configure_dt(&led, GPIO_OUTPUT_INACTIVE) < 0) {
		printk("Cannot configure LED pin\n");
		return;
	}

	printk("Blink thread started on %s\n", CONFIG_BOARD_TARGET);

	while (1) {
		gpio_pin_toggle_dt(&led);
		k_msleep(BLINK_PERIOD_MS);
	}
}

/* Created at boot and started automatically (delay 0). */
K_THREAD_DEFINE(blink_tid, BLINK_STACK_SIZE, blink_thread, NULL, NULL, NULL,
		BLINK_PRIORITY, 0, 0);

int main(void)
{
	/* Nothing to do here: main() returns and the blink thread keeps running. */
	return 0;
}
