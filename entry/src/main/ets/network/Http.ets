import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'Http';

/** Result of a raw HTTP call. */
export class HttpResult {
  code: number = 0;
  body: string = '';

  constructor(code: number, body: string) {
    this.code = code;
    this.body = body;
  }

  get ok(): boolean {
    return this.code >= 200 && this.code < 300;
  }
}

const DEFAULT_TIMEOUT: number = 20000;

/**
 * Small wrapper over @ohos.net.http so the rest of the app never touches the
 * module directly. Deliberately string-in / string-out: parsing is the callers'
 * job so each response can be strongly typed.
 */
export class Http {
  /**
   * POST with a JSON body. Omit the body for endpoints that take none: an empty
   * string is rejected by net.http as a parameter error (BusinessError 401).
   */
  static async postJson(url: string, headers: Record<string, string>,
    body?: string): Promise<HttpResult> {
    const payload: string | undefined = body !== undefined && body.length > 0 ? body : undefined;
    return Http.request(url, http.RequestMethod.POST, headers, payload);
  }

  static async get(url: string, headers: Record<string, string>): Promise<HttpResult> {
    return Http.request(url, http.RequestMethod.GET, headers, undefined);
  }

  static async request(url: string, method: http.RequestMethod, headers: Record<string, string>,
    body: string | undefined): Promise<HttpResult> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        connectTimeout: DEFAULT_TIMEOUT,
        readTimeout: DEFAULT_TIMEOUT,
        expectDataType: http.HttpDataType.STRING
      };
      if (body !== undefined) {
        options.extraData = body;
      }
      const response = await request.request(url, options);
      const raw: string | Object | ArrayBuffer = response.result;
      const text: string = typeof raw === 'string' ? raw : JSON.stringify(raw);
      return new HttpResult(response.responseCode as number, text);
    } catch (e) {
      const err = e as BusinessError;
      throw new Error(`Request to ${url} failed${err.code !== undefined ? ` (${err.code})` : ''}`);
    } finally {
      request.destroy();
    }
  }

  static async requestText(url: string, headers: Record<string, string>): Promise<string> {
    try {
      const result = await Http.get(url, headers);
      return result.ok ? result.body : '';
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'requestText failed: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  /**
   * GET as bytes, for downloads and images. Returns undefined on any failure so
   * a single missing segment does not have to abort a whole download.
   */
  static async requestBuffer(url: string, headers: Record<string, string>): Promise<ArrayBuffer | undefined> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: DEFAULT_TIMEOUT,
        readTimeout: 60000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      const response = await request.request(url, options);
      const raw: string | Object | ArrayBuffer = response.result;
      if (raw instanceof ArrayBuffer) {
        return raw;
      }
      hilog.warn(DOMAIN, TAG, 'unexpected body type from %{public}s', url);
      return undefined;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'requestBuffer failed: %{public}s', JSON.stringify(e));
      return undefined;
    } finally {
      request.destroy();
    }
  }
}
