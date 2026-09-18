import datetime as dt
import importlib.machinery
import importlib.util
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader('collector', str(Path(__file__).resolve().parents[1] / 'bin/collect'))
spec = importlib.util.spec_from_loader(loader.name, loader)
c = importlib.util.module_from_spec(spec)
loader.exec_module(c)


class CollectorTests(unittest.TestCase):
    def test_api_key_required(self):
        with patch.dict(c.os.environ, {'CHEAPERINFERENCE_API_KEY': ''}, clear=True), \
             patch.object(c, 'read_config', return_value={}), patch.object(c, 'probe_activity') as probe:
            self.assertEqual(c.api_key(), '')
            self.assertEqual(c.collect_usage('7d', False)['usageStatusText'], 'API key required')
            probe.assert_not_called()

    def test_env_key_takes_precedence_over_config_file(self):
        with patch.dict(c.os.environ, {'CHEAPERINFERENCE_API_KEY': 'env-key'}, clear=True), \
             patch.object(c, 'read_config', return_value={'apiKey': 'file-key'}):
            self.assertEqual(c.api_key(), 'env-key')
        with patch.dict(c.os.environ, {'CHEAPERINFERENCE_API_KEY': ''}, clear=True), \
             patch.object(c, 'read_config', return_value={'apiKey': 'file-key'}):
            self.assertEqual(c.api_key(), 'file-key')

    def test_daily_aggregation_and_zero_days(self):
        window = {'start': '2026-09-01T00:00:00Z', 'end': '2026-09-03T12:00:00Z'}
        payload = {'object': 'usage.daily', 'daily_spend': [
            {'date': '2026-09-01', 'spend_usd': 4.0, 'request_count': 80, 'prompt_tokens': 400, 'cached_tokens': 0},
            {'date': '2026-09-03', 'spend_usd': 1.0, 'request_count': 1, 'prompt_tokens': 5, 'cached_tokens': 2},
        ]}
        days = c.daily_usage(payload, window)
        self.assertEqual([day['cost'] for day in days], [4, 0, 1])
        self.assertEqual(days[0]['prompts'], 80)
        self.assertEqual(days[0]['messageCount'], 400)
        self.assertEqual(days[2]['messageCount'], 7)

    def test_partial_or_malformed_daily_response_rejected(self):
        window = c.period_time_range('7d')
        for result in ({}, {'object': 'usage.daily'}, {'object': 'usage.daily', 'daily_spend': 'nope'},
                       {'object': 'usage.daily', 'daily_spend': [{'date': '1999-01-01', 'spend_usd': 1}]}):
            with self.subTest(result=result), self.assertRaises(ValueError):
                c.daily_usage(result, window)

    def test_daily_totals_use_api_reported_cache_hit(self):
        window = c.period_time_range('7d')
        payload = {'object': 'usage.daily', 'cache_hit_pct': 75.4, 'daily_spend': []}
        activity_days = c.daily_usage(payload, window)
        self.assertEqual(len(activity_days), 7)
        self.assertEqual(c.ratio(payload.get('cache_hit_pct')), 0.754)

    def test_period_windows_are_day_grain(self):
        for period, days_count in [('3d', 3), ('7d', 7), ('1mo', 30), ('3mo', 90)]:
            with self.subTest(period=period):
                window = c.period_time_range(period)
                start = dt.date.fromisoformat(window['start'][:10])
                end = dt.date.fromisoformat(window['end'][:10])
                self.assertEqual((end - start).days + 1, days_count)
                self.assertTrue(window['start'].endswith('T00:00:00Z'))
                days = c.daily_usage({'object': 'usage.daily', 'daily_spend': []}, window)
                self.assertEqual(len(days), days_count)

    def test_cache_isolation_force_and_auth_rejection(self):
        records = {}
        activity = {'recentDays': [], 'spend': 40}
        def read(path, age):
            return records.get(str(path))
        def write(path, record):
            records[str(path)] = record
        with patch.object(c, 'cache_root', return_value=Path('/unused')), \
             patch.object(c, 'read_fresh_json', side_effect=read), patch.object(c, 'write_json', side_effect=write), \
             patch.object(c, 'api_key', return_value='key-one') as key, \
             patch.object(c, 'probe_activity', return_value=activity) as probe, \
             patch.object(c, 'probe_balance', return_value={'ok': True, 'balance': {'remaining': 10}}):
            self.assertTrue(c.collect_usage('7d', False)['ready'])
            c.collect_usage('7d', False)
            self.assertEqual(probe.call_count, 1)
            c.collect_usage('7d', True)
            self.assertEqual(probe.call_count, 2)
            probe.side_effect = urllib.error.URLError('offline')
            stale = c.collect_usage('7d', True)
            self.assertEqual(stale['activity']['spend'], 40)
            self.assertIn('Showing cached totals from', stale['authHelpText'])
            key.return_value = 'key-two'
            self.assertNotIn('activity', c.collect_usage('7d', False))
            key.return_value = 'key-one'
            probe.side_effect = urllib.error.HTTPError('url', 403, 'Forbidden', {}, None)
            rejected = c.collect_usage('7d', True)
            self.assertNotIn('activity', rejected)
            self.assertNotIn('balance', rejected)
            self.assertNotIn('activity', c.collect_usage('7d', False))

    def test_optional_breakdown_failure_preserves_daily_usage(self):
        def request(path, key, method='GET', query=None):
            if path == '/usage/daily':
                return {'object': 'usage.daily', 'daily_spend': []}
            raise TimeoutError('timeout')
        with patch.object(c, 'api_request', side_effect=request):
            activity = c.probe_activity('key', '7d')
        self.assertEqual(len(activity['recentDays']), 7)
        self.assertEqual(activity['spend'], 0)
        self.assertIn('models', activity['breakdownErrors'])
        self.assertIn('keys', activity['breakdownErrors'])

    def test_activity_queries_use_documented_endpoints_and_params(self):
        calls = []
        def request(path, key, method='GET', query=None):
            calls.append((path, query))
            if path == '/usage/daily':
                self.assertIn('start_at', query)
                self.assertIn('end_at', query)
                return {'object': 'usage.daily', 'daily_spend': [
                    {'date': query['start_at'][:10], 'spend_usd': 40, 'request_count': 80,
                     'prompt_tokens': 400, 'cached_tokens': 0},
                ]}
            return {'object': 'list', 'data': [], 'has_more': False, 'next_cursor': None}
        with patch.object(c, 'api_request', side_effect=request):
            activity = c.probe_activity('key', '7d')
        self.assertEqual(activity['spend'], 40)
        self.assertEqual(activity['requests'], 80)
        self.assertEqual(activity['tokens'], 400)
        paths = [path for path, _ in calls]
        self.assertIn('/usage/daily', paths)
        self.assertIn('/usage/requests', paths)

    def test_request_history_pagination_walks_all_pages(self):
        def request(path, key, method='GET', query=None):
            if path == '/usage/daily':
                return {'object': 'usage.daily', 'daily_spend': []}
            self.assertEqual(query['limit'], 100)
            page_one = query.get('cursor') is None
            return {
                'object': 'list',
                'data': [{'model': 'gpt-5.4', 'api_key_name': 'prod',
                          'billed_cost_usd': 1 if page_one else 2,
                          'total_tokens': 10}],
                'has_more': page_one,
                'next_cursor': 'page-2' if page_one else None,
            }
        with patch.object(c, 'api_request', side_effect=request):
            activity = c.probe_activity('key', '7d')
        self.assertEqual(len(activity['topModels']), 2)
        self.assertEqual(activity['topModels'][0]['cost'], 2)  # highest spend first
        self.assertEqual(sum(row['cost'] for row in activity['topKeys']), 3)

    def test_pagination_stall_and_unknown_cursor_are_errors(self):
        calls = {'n': 0}
        def request(path, key, method='GET', query=None):
            if path == '/usage/daily':
                return {'object': 'usage.daily', 'daily_spend': []}
            calls['n'] += 1
            return {'object': 'list', 'data': [], 'has_more': True, 'next_cursor': 'same-cursor'}
        with patch.object(c, 'api_request', side_effect=request):
            activity = c.probe_activity('key', '7d')
        self.assertIn('models', activity['breakdownErrors'])

    def test_breakdowns_ranked_by_spend_and_unknown_names(self):
        rows = [{'model': f'model-{i}', 'api_key_name': f'key-{i}',
                 'billed_cost_usd': i, 'total_tokens': 1000 - i} for i in range(40)]
        rows.append({'model': None, 'api_key_name': '', 'billed_cost_usd': 2, 'total_tokens': 5})
        ranked = c.ranked_spend(rows, 'model', 1000)
        self.assertEqual(ranked[0]['cost'], 39)
        self.assertEqual(sum(row['cost'] for row in ranked), 780 + 2)
        self.assertEqual(c.ranked_spend([{'model': None, 'billed_cost_usd': 2}], 'model', 1000)[0]['name'], 'Unknown')

    def test_balance_uses_account_endpoint_and_available_usd(self):
        with patch.object(c, 'api_request', return_value={
            'object': 'account.balance', 'currency': 'USD',
            'balance_usd': 124.50, 'available_usd': 118.02, 'reserved_usd': 6.48,
        }) as request, patch.object(c, 'read_config', return_value={}):
            result = c.probe_balance('key')
        request.assert_called_once_with('/account/balance', 'key')
        self.assertEqual(result['balance']['remaining'], 118.02)
        self.assertEqual(result['balance']['reserved'], 6.48)

    def test_usage_only_key_balance_403_is_not_a_fatal_error(self):
        with patch.object(c, 'api_request',
                          side_effect=urllib.error.HTTPError('url', 403, 'Forbidden', {}, None)):
            result = c.probe_balance('key')
        self.assertFalse(result['ok'])
        self.assertTrue(result.get('forbidden'))

    def test_balance_rejects_unexpected_envelope(self):
        with patch.object(c, 'api_request', return_value={'object': 'something.else'}):
            result = c.probe_balance('key')
        self.assertFalse(result['ok'])

    def test_http_response_verifies_origin_and_sends_bearer(self):
        from unittest.mock import MagicMock
        response = MagicMock()
        response.geturl.return_value = c.API_BASE_URL + '/usage/daily'
        response.read.return_value = b'{"object": "usage.daily", "daily_spend": []}'
        response.__enter__.return_value = response
        with patch.object(c._opener, 'open', return_value=response) as opened:
            payload = c.api_request('/usage/daily', 'key', query={'start_at': 'x'})
        self.assertEqual(payload['object'], 'usage.daily')
        request = opened.call_args.args[0]
        self.assertEqual(request.get_header('Authorization'), 'Bearer key')
        self.assertIn('start_at=x', request.full_url)

    def test_collector_record_shape(self):
        with patch.object(c, 'api_key', return_value=''), patch.object(c, 'probe_activity') as probe:
            record = c.collect_usage('7d', False)
        self.assertEqual(record['usageStatusText'], 'API key required')
        probe.assert_not_called()


if __name__ == '__main__':
    unittest.main()
