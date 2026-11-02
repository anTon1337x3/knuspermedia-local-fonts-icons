<?php
/**
 * Plugin Name: knuspermedia Local Fonts & Icons E2E page cache
 * Description: Behaves like WP Rocket and similar page caches: its output buffer starts before the plugin's and
 * stores the final HTML when WordPress flushes the buffers on shutdown. Purging deletes the stored page.
 */

$wpdf_page_cache_file = WP_CONTENT_DIR . '/uploads/wpdf-e2e-page-cache.html';

add_action(
	'muplugins_loaded',
	static function () use ( $wpdf_page_cache_file ) {
		if ( is_admin() || wp_doing_ajax() || wp_doing_cron() || ( defined( 'WP_CLI' ) && WP_CLI ) || ! isset( $_GET['wpdf-cache'] ) ) {
			return;
		}

		ob_start(
			static function ( $html ) use ( $wpdf_page_cache_file ) {
				file_put_contents( $wpdf_page_cache_file, $html );

				return $html;
			}
		);
	}
);

add_action(
	'wpdf_purge_page_caches',
	static function () use ( $wpdf_page_cache_file ) {
		if ( file_exists( $wpdf_page_cache_file ) ) {
			unlink( $wpdf_page_cache_file );
		}
	}
);
