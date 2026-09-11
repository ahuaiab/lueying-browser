import { describe, expect, it } from '@ohos/hypium';
import {
  bookmarkRecordForPage,
  committedUrlForTabState,
  displayUrlFor,
  loadableUrlFor,
  normalizeAddressInput,
  tabOverviewTitleFor,
  urlSchemeFor,
  validateBrowserUrl
} from '../../../main/ets/browser/model/BrowserTypes';

export default function browserTypesTest() {
  describe('BrowserTypes', () => {
    it('keeps explicit HTTP(S) addresses', 0, () => {
      expect(normalizeAddressInput('https://example.com')).assertEqual('https://example.com');
      expect(normalizeAddressInput(' http://example.com ')).assertEqual('http://example.com');
    });

    it('adds HTTPS to a hostname', 0, () => {
      expect(normalizeAddressInput('example.com')).assertEqual('https://example.com');
    });

    it('uses a search URL for free-form input', 0, () => {
      expect(normalizeAddressInput('hello world'))
        .assertEqual('https://cn.bing.com/search?q=hello%20world');
    });

    it('shows search terms and engines instead of search result URLs in tab overview', 0, () => {
      expect(tabOverviewTitleFor(
        'https://cn.bing.com/search?q=%E9%B8%BF%E8%92%99%20ArkUI&form=QBLH',
        'https://cn.bing.com/search?q=%E9%B8%BF%E8%92%99%20ArkUI&form=QBLH'
      )).assertEqual('鸿蒙 ArkUI-bing');
      expect(tabOverviewTitleFor(
        'https://www.bing.com/search?q=hello+world',
        'Search results'
      )).assertEqual('hello world-bing');
      expect(tabOverviewTitleFor(
        'https://www.bing.com/?q=codex-title-check&mkt=zh-CN',
        'bing.com/?q=codex-title-check&mkt=zh-CN'
      )).assertEqual('codex-title-check-bing');
      expect(tabOverviewTitleFor(
        'https://www.baidu.com/s?wd=HarmonyOS',
        'HarmonyOS_百度搜索'
      )).assertEqual('HarmonyOS-baidu');
    });

    it('creates page bookmarks with the page title and complete URL', 0, () => {
      const pageBookmark = bookmarkRecordForPage(
        'https://192.168.225.1/admin',
        'Simple Admin',
        1
      );
      expect(pageBookmark === undefined).assertFalse();
      if (pageBookmark !== undefined) {
        expect(pageBookmark.title).assertEqual('Simple Admin');
        expect(pageBookmark.url).assertEqual('https://192.168.225.1/admin');
      }

      const searchBookmark = bookmarkRecordForPage(
        'https://cn.bing.com/search?q=dsdsds',
        '',
        2
      );
      expect(searchBookmark === undefined).assertFalse();
      if (searchBookmark !== undefined) {
        expect(searchBookmark.title).assertEqual('dsdsds-bing');
        expect(searchBookmark.url).assertEqual('https://cn.bing.com/search?q=dsdsds');
      }

      expect(bookmarkRecordForPage('about:blank', '起始页', 3)).assertUndefined();
    });

    it('keeps the page title for non-search tabs', 0, () => {
      expect(tabOverviewTitleFor('https://example.com/path', 'Example Domain'))
        .assertEqual('Example Domain');
      expect(tabOverviewTitleFor('about:blank', ''))
        .assertEqual('起始页');
    });

    it('rejects display text and preserves the previous complete URL in tab state', 0, () => {
      const previous: string = 'https://example.com/path?query=value#section';
      expect(validateBrowserUrl(previous).valid).assertTrue();
      expect(validateBrowserUrl('start.weixin').valid).assertFalse();
      expect(validateBrowserUrl('Example Domain').valid).assertFalse();
      expect(validateBrowserUrl('').valid).assertFalse();
      expect(urlSchemeFor('start.weixin')).assertEqual('');
      expect(loadableUrlFor('start.weixin')).assertUndefined();
      expect(committedUrlForTabState('start.weixin', previous)).assertEqual(previous);
      expect(displayUrlFor(previous)).assertEqual('example.com');
    });

    it('keeps complete URL paths and queries when validating load input', 0, () => {
      const fullUrl: string = 'https://example.com/path?query=value#section';
      expect(loadableUrlFor(fullUrl)).assertEqual(fullUrl);
      expect(urlSchemeFor(fullUrl)).assertEqual('https');
    });
  });
}
