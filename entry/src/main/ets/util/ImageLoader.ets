import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Http } from '../network/Http';

const DOMAIN: number = 0x0000;
const TAG: string = 'ImageLoader';

/**
 * Small bitmap loader.
 *
 * The system live view and the media session both want real pixels rather than a
 * URL, so the avatar of whatever is playing has to be fetched and decoded once
 * and then handed over as an image.PixelMap. They want it at different sizes -
 * the live view capsule has a hard budget the media card does not - so the size
 * is part of what the cache is keyed on, and each caller gets the copy it asked
 * for.
 */
export class ImageLoader {
  private static cache: Map<string, image.PixelMap> = new Map();

  /** Already-decoded image of this size, if this URL was loaded before. */
  static cached(url: string, size: number): image.PixelMap | undefined {
    return ImageLoader.cache.get(`${size}|${url}`);
  }

  /**
   * Downloads and decodes an image, scaled down to `size` on the longer edge.
   * Returns undefined for anything that cannot be fetched or decoded.
   */
  static async load(url: string, size: number): Promise<image.PixelMap | undefined> {
    if (url.length === 0) {
      return undefined;
    }
    const key: string = `${size}|${url}`;
    const hit: image.PixelMap | undefined = ImageLoader.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const buffer: ArrayBuffer | undefined = await Http.requestBuffer(url, {});
    if (buffer === undefined || buffer.byteLength === 0) {
      return undefined;
    }
    try {
      const source: image.ImageSource = image.createImageSource(buffer);
      const options: image.DecodingOptions = {
        desiredSize: { width: size, height: size }
      };
      const pixelMap: image.PixelMap = await source.createPixelMap(options);
      await source.release();
      ImageLoader.cache.set(key, pixelMap);
      return pixelMap;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not decode %{public}s', url);
      return undefined;
    }
  }
}
