#!/usr/bin/env bash
# Starts WordPress with the fixtures, activates the plugin and checks that no page or stylesheet
# references Google Fonts or Font Awesome anymore, and that every local copy is served.
#
#   tests/e2e/run.sh          run the checks (keeps the site running on http://localhost:8089, admin/admin)
#   tests/e2e/run.sh down     remove containers and volumes
set -euo pipefail

cd "$(dirname "$0")"
SITE=http://localhost:8089

if [[ "${1:-}" == "down" ]]; then
	docker compose down -v
	exit 0
fi

docker compose up -d --wait db wordpress >/dev/null 2>&1

until curl -fs -o /dev/null "$SITE/wp-admin/install.php"; do sleep 1; done

wp() { docker compose run --rm -T cli "$@" 2>/dev/null; }

if ! wp core is-installed; then
	wp core install --url="$SITE" --title="WPDF E2E" --admin_user=admin --admin_password=admin --admin_email=admin@example.com --skip-email >/dev/null
	wp rewrite structure '/%postname%/' >/dev/null
fi

wp plugin activate knuspermedia-local-fonts-icons >/dev/null
wp local-fonts-icons flush >/dev/null
docker compose exec -T wordpress rm -f /var/www/html/wp-content/debug.log

status=0
php check.php "$SITE" || status=1

echo "Page cache (simulated, see fixtures/wpdf-page-cache.php):"
# Forget all known scripts, so the theme's hardcoded Font Awesome scripts are discovered again.
wp local-fonts-icons flush >/dev/null
wp option update wpdf_fixture_purges 0 >/dev/null
cached() { docker compose exec -T wordpress sh -c 'f=/var/www/html/wp-content/uploads/wpdf-e2e-page-cache.html; [ -f $f ] && grep -c "wpdf-fa-" $f || echo none'; }
curl -fs -o /dev/null "$SITE/?wpdf-cache=1"
first_cached=$(cached); first_purges=$(wp option get wpdf_fixture_purges)
curl -fs -o /dev/null "$SITE/?wpdf-cache=1"
second_cached=$(cached); second_purges=$(wp option get wpdf_fixture_purges)
if [[ "$first_cached" == none && "$first_purges" == 1 ]]; then echo "  ✓ first view (scripts removed, stylesheets not yet enqueued) is purged from the cache"; else echo "  ✗ first view: cached=$first_cached purges=$first_purges (expected none and 1)"; status=1; fi
if [[ "$second_cached" != none && "$second_cached" -gt 0 && "$second_purges" == 1 ]]; then echo "  ✓ second view is cached with the replacement stylesheets and doesn't purge again"; else echo "  ✗ second view: stylesheet links in cache=$second_cached purges=$second_purges (expected >0 and 1)"; status=1; fi

echo "Page check (WP-CLI):"
if wp local-fonts-icons scan; then echo "  ✓ scanner finds no references"; else echo "  ✗ scanner reports references"; status=1; fi

echo "Stylesheet paths:"
resolved=$(wp eval 'add_filter( "plugins_url", static function ( $url ) { return str_replace( "http://localhost:8089", "https://cdn.example.com", $url ); } ); $map = [ "https://cdn.example.com/wp-content/plugins/wpdf-fixtures/theme.css?ver=1", "//cdn.example.com/wp-content/plugins/wpdf-fixtures/parts/fonts.css", "https://other.example.com/wp-content/plugins/wpdf-fixtures/theme.css", "https://cdn.example.com/wp-content/plugins/../../wp-admin/css/login.css" ]; foreach ( $map as $url ) { echo WPDsgvoFonts\Localizer::url_to_path( $url ) ? 1 : 0; }')
if [[ "$resolved" == 1100 ]]; then echo "  ✓ own content host resolved, foreign host and path traversal rejected"; else echo "  ✗ resolved $resolved (expected 1100)"; status=1; fi

echo "Admin page (WP_DEBUG):"
rendered=$(wp eval 'require_once ABSPATH . "wp-admin/includes/admin.php"; wp_set_current_user( 1 ); ob_start(); ( new WPDsgvoFonts\Admin() )->render(); echo strlen( ob_get_clean() );')
if (( rendered > 2000 )); then echo "  ✓ settings page renders"; else echo "  ✗ settings page did not render"; status=1; fi

echo "PHP notices (WP_DEBUG, debug.log):"
log=$(docker compose exec -T wordpress sh -c 'cat /var/www/html/wp-content/debug.log 2>/dev/null' | grep -iE "knuspermedia-local-fonts-icons|WPDsgvoFonts" || true)
if [[ -z "$log" ]]; then echo "  ✓ none caused by the plugin"; else echo "$log"; echo "  ✗ the plugin caused PHP notices"; status=1; fi

echo "Plugin notices:"
wp option get wpdf_errors --format=json || echo "  (none)"

exit $status
