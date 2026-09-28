import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PrefKeys } from '../common/Const';
import { Prefs } from '../common/Prefs';
import { Http } from '../network/Http';
import { HlsParser } from '../player/HlsParser';
import { ChatMessage } from '../model/ChatMessage';
import { DownloadEntry } from '../model/DownloadEntry';
import { Quality } from '../model/Quality';
import { CommentRepository } from './CommentRepository';
import { LibraryMigration } from './LibraryMigration';
import { PlaybackRepository, PlaybackToken } from './PlaybackRepository';

const DOMAIN: number = 0x0000;
const TAG: string = 'Download';
/**
 * Highest rendition height a download is allowed to use.
 *
 * A full archive at the source quality of a long stream runs into tens of
 * gigabytes, which no phone wants; 720p60 keeps a two-hour broadcast around a
 * gigabyte while still looking right on a handheld screen.
 */
const MAX_HEIGHT: number = 720;

/** Progress of one download, reported after every segment. */
export class DownloadProgress {
  videoId: string = '';
  percent: number = 0;
  bytes: number = 0;
  totalBytes: number = 0;
  segment: number = 0;
  segments: number = 0;
  /** Smoothed transfer rate, 0 until the first segment has been timed. */
  bytesPerSecond: number = 0;
  paused: boolean = false;
  /** PHASE_VIDEO while fetching media, PHASE_COMMENTS while fetching the replay. */
  phase: string = 'video';
  /** True when the file being written holds sound only. */
  audioOnly: boolean = false;

  constructor(percent: number, bytes: number, totalBytes: number, segment: number, segments: number) {
    this.percent = percent;
    this.bytes = bytes;
    this.totalBytes = totalBytes;
    this.segment = segment;
    this.segments = segments;
  }
}

/** Fetching the media itself. */
export const PHASE_VIDEO: string = 'video';
/** Fetching the chat replay that belongs to it. */
export const PHASE_COMMENTS: string = 'comments';

/**
 * One transfer's state, kept while it is paused so it can be picked up again.
 *
 * The unit of work is the segment: pausing stops between two of them, and the
 * index is the resume point, so nothing already fetched is fetched twice.
 */
class DownloadSession {
  videoId: string = '';
  baseDir: string = '';
  candidates: Quality[] = [];
  /**
   * Name of the rendition the user picked in the download sheet, '' when the
   * transfer is choosing for itself. An explicit pick is a promise: only that
   * quality is fetched, by whichever URL answers, so an "audio only" download
   * can never quietly come back as a video.
   */
  picked: string = '';
  /** The rendition actually being fetched; unset until one answers. */
  target: Quality | undefined = undefined;
  audioOnly: boolean = false;
  filePath: string = '';
  parts: string[] = [];
  /** Next segment to fetch. */
  index: number = 0;
  bytes: number = 0;
  totalBytes: number = 0;
  bytesPerSecond: number = 0;
  durationSeconds: number = 0;
  phase: string = PHASE_VIDEO;
  /** True once every segment has been written. */
  videoDone: boolean = false;
  paused: boolean = false;
  finished: boolean = false;
}

/**
 * Downloads a VOD into the app sandbox as one playable file, and keeps the list
 * of what has been downloaded.
 *
 * Xtra hands downloads to ExoPlayer's DownloadManager, which keeps the HLS
 * structure on disk. HarmonyOS has no equivalent for an arbitrary HLS stream, so
 * the segments are fetched in order and appended to a single file: HLS segments
 * are designed to be concatenated, so a .ts chain stays a valid transport stream
 * and a fragmented-MP4 chain stays a valid MP4 (with its EXT-X-MAP init segment
 * written first, exactly once).
 *
 * The finished files are listed from their own store, keyed separately from the
 * favourites: a download is a file on this device and has nothing to do with
 * whether the video was bookmarked.
 */
export class DownloadRepository {
  /** Bumped on every progress report, so any page can follow a transfer. */
  static readonly KEY_DOWNLOAD_VERSION: string = 'downloadVersion';
  private static running: string[] = [];
  private static cancelled: string[] = [];
  /**
   * Progress of the transfers in flight, keyed by video id.
   *
   * A download outlives the screen that started it, so the state cannot live in
   * a page: whoever wants to show it reads it from here (and re-renders on the
   * version counter, which is what makes a background transfer visible).
   */
  private static progress: Map<string, DownloadProgress> = new Map();
  /** Live sessions, including the paused ones waiting to be resumed. */
  private static sessions: Map<string, DownloadSession> = new Map();

  static isDownloading(videoId: string): boolean {
    return DownloadRepository.running.indexOf(videoId) >= 0;
  }

  /** True while a transfer is either running or sitting paused. */
  static isActive(videoId: string): boolean {
    return DownloadRepository.isDownloading(videoId)
      || DownloadRepository.sessions.get(videoId) !== undefined;
  }

  static isPaused(videoId: string): boolean {
    const session: DownloadSession | undefined = DownloadRepository.sessions.get(videoId);
    return session !== undefined && session.paused;
  }

  static progressOf(videoId: string): DownloadProgress | undefined {
    return DownloadRepository.progress.get(videoId);
  }

  /**
   * Every transfer in flight.
   *
   * Pages that list the downloads take a copy of this into their own state: the
   * progress lives out here, so nothing would re-render a row as it advances.
   */
  static activeTransfers(): DownloadProgress[] {
    const transfers: DownloadProgress[] = [];
    DownloadRepository.progress.forEach((value: DownloadProgress) => {
      transfers.push(value);
    });
    return transfers;
  }

  /* ---------------------------- the store ---------------------------- */

  /**
   * Every download, newest first: the finished ones and the ones still running.
   *
   * The record is written when a transfer starts, so an in-flight download is
   * listed from the moment it is queued - a download you cannot see is a download
   * you cannot pause.
   */
  static all(): DownloadEntry[] {
    LibraryMigration.run();
    const text: string = Prefs.getString(PrefKeys.DOWNLOADS, '');
    if (text.length === 0) {
      return [];
    }
    const entries: DownloadEntry[] = [];
    try {
      const parsed: DownloadEntry[] = JSON.parse(text) as DownloadEntry[];
      for (let i = 0; i < parsed.length; i++) {
        const entry: DownloadEntry = DownloadEntry.normalize(parsed[i]);
        if (entry.id.length > 0) {
          entries.push(entry);
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'the download list is unreadable, starting over');
      return [];
    }
    entries.sort((a: DownloadEntry, b: DownloadEntry) => b.startedAt - a.startedAt);
    return entries;
  }

  static find(id: string): DownloadEntry | undefined {
    const all: DownloadEntry[] = DownloadRepository.all();
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === id) {
        return all[i];
      }
    }
    return undefined;
  }

  /**
   * What the downloads list shows: the files that are on the device, plus the
   * transfers currently in flight.
   *
   * A record with no file and no session is the leftover of a transfer the
   * process did not survive, and is not listed; starting that download again
   * overwrites it.
   */
  static listed(): DownloadEntry[] {
    const all: DownloadEntry[] = DownloadRepository.all();
    const entries: DownloadEntry[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].downloaded || DownloadRepository.isActive(all[i].id)) {
        entries.push(all[i]);
      }
    }
    return entries;
  }

  /** Inserts or replaces the record, keeping the order it was queued in. */
  private static record(entry: DownloadEntry): void {
    const all: DownloadEntry[] = DownloadRepository.all();
    let replaced: boolean = false;
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === entry.id) {
        const startedAt: number = all[i].startedAt;
        entry.startedAt = startedAt > 0 ? startedAt : Date.now();
        all[i] = entry;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      if (entry.startedAt === 0) {
        entry.startedAt = Date.now();
      }
      all.push(entry);
    }
    DownloadRepository.persist(all);
  }

  /** Records the finished file against the entry that queued it. */
  static attachDownload(id: string, filePath: string, audioOnly: boolean): void {
    const existing: DownloadEntry | undefined = DownloadRepository.find(id);
    if (existing === undefined) {
      hilog.warn(DOMAIN, TAG, 'a download finished for an unknown video %{public}s', id);
      return;
    }
    existing.filePath = filePath;
    existing.fileSize = DownloadRepository.fileSize(filePath);
    existing.audioOnly = audioOnly;
    DownloadRepository.record(existing);
  }

  /**
   * Removes whatever an earlier download of this video left on disk.
   *
   * The new file can land on the same path - appending to it would silently
   * double it - or, when the rendition changed, beside it. Either way the old
   * bytes go, and the record stops claiming a file that is no longer there.
   */
  private static discard(videoId: string, path: string): void {
    DownloadRepository.deleteFile(path);
    DownloadRepository.deleteFile(CommentRepository.pathFor(path));
    const previous: DownloadEntry | undefined = DownloadRepository.find(videoId);
    if (previous === undefined || previous.filePath.length === 0 || previous.filePath === path) {
      return;
    }
    DownloadRepository.deleteFile(previous.filePath);
    DownloadRepository.deleteFile(CommentRepository.pathFor(previous.filePath));
    previous.filePath = '';
    previous.fileSize = 0;
    previous.audioOnly = false;
    DownloadRepository.record(previous);
  }

  /** Deletes the file and drops its record. Favourites are not affected. */
  static removeDownload(id: string): void {
    if (DownloadRepository.isActive(id)) {
      // The partial file is the loop's to delete: it is the only thing that knows
      // how much of it has been written.
      DownloadRepository.cancel(id);
    }
    const existing: DownloadEntry | undefined = DownloadRepository.find(id);
    if (existing === undefined) {
      return;
    }
    if (existing.filePath.length > 0) {
      DownloadRepository.deleteFile(existing.filePath);
      DownloadRepository.deleteFile(CommentRepository.pathFor(existing.filePath));
    }
    DownloadRepository.remove(id);
  }

  private static remove(id: string): void {
    const all: DownloadEntry[] = DownloadRepository.all();
    const remaining: DownloadEntry[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].id !== id) {
        remaining.push(all[i]);
      }
    }
    DownloadRepository.persist(remaining);
  }

  private static persist(entries: DownloadEntry[]): void {
    try {
      Prefs.setString(PrefKeys.DOWNLOADS, JSON.stringify(entries));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not store the download list');
    }
    DownloadRepository.bump();
  }

  private static fileSize(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  /** Asks a download in flight to stop; the partial file is deleted. */
  static cancel(videoId: string): void {
    if (DownloadRepository.cancelled.indexOf(videoId) < 0) {
      DownloadRepository.cancelled.push(videoId);
    }
  }

  /**
   * Rough bitrate of a well-known rendition name.
   *
   * The CDN links derived from the storyboard carry no bitrate, and without one
   * neither the progress bar nor the size estimate has anything to scale against,
   * so the standard Twitch ladder stands in as an approximation.
   */
  static nominalBitrate(name: string): number {
    if (name === 'audio_only') {
      return 160000;
    }
    if (name === 'source') {
      return 8000000;
    }
    if (name === '1080p60') {
      return 6000000;
    }
    if (name === '1080p30') {
      return 4500000;
    }
    if (name === '720p60') {
      return 3400000;
    }
    if (name === '720p30') {
      return 2500000;
    }
    if (name === '480p30') {
      return 1400000;
    }
    if (name === '360p30') {
      return 900000;
    }
    if (name === '160p30') {
      return 300000;
    }
    return 0;
  }

  /**
   * Starts a download.
   *
   * The transfer outlives whatever started it: its record is written here, before
   * anything is fetched, and the finished file is attached to that same record,
   * so a download resumed from the list ends exactly like one started in the
   * player.
   *
   * `picked` is the rendition name the user chose, if any; it constrains the
   * transfer to that one quality rather than letting it settle for another.
   */
  static async start(context: common.UIAbilityContext, video: DownloadEntry,
    candidates: Quality[], picked: string = ''): Promise<string> {
    if (DownloadRepository.isActive(video.id)) {
      throw new Error('a download is already running');
    }
    // A record left by an earlier download still describes a file on disk, and a
    // transfer that has only been queued knows nothing about any file: what the
    // last one left keeps standing - flag included - until this one replaces it.
    const previous: DownloadEntry | undefined = DownloadRepository.find(video.id);
    if (previous !== undefined && video.filePath.length === 0 && previous.filePath.length > 0) {
      video.filePath = previous.filePath;
      video.fileSize = previous.fileSize;
      video.audioOnly = previous.audioOnly;
    }
    DownloadRepository.record(video);
    const session: DownloadSession = new DownloadSession();
    session.videoId = video.id;
    session.baseDir = context.filesDir;
    session.candidates = candidates;
    session.picked = picked;
    session.durationSeconds = video.durationSeconds;
    DownloadRepository.sessions.set(video.id, session);
    DownloadRepository.cancelled = DownloadRepository.cancelled.filter((id: string) => id !== video.id);
    await DownloadRepository.beginBackgroundTask(context);
    return DownloadRepository.launch(video.id);
  }

  /** Continues a paused or interrupted download from where it stopped. */
  static async resume(context: common.UIAbilityContext, videoId: string): Promise<string> {
    if (DownloadRepository.sessions.get(videoId) === undefined) {
      throw new Error('nothing to resume');
    }
    await DownloadRepository.beginBackgroundTask(context);
    return DownloadRepository.launch(videoId);
  }

  /** Stops between two segments; the partial file and the queue are kept. */
  static pause(videoId: string): void {
    const session: DownloadSession | undefined = DownloadRepository.sessions.get(videoId);
    if (session === undefined) {
      return;
    }
    session.paused = true;
    DownloadRepository.setProgress(videoId, DownloadRepository.snapshot(session, true));
  }

  /** Runs the loop for a session, from the start or from its resume point. */
  private static async launch(videoId: string): Promise<string> {
    const session: DownloadSession | undefined = DownloadRepository.sessions.get(videoId);
    if (session === undefined) {
      throw new Error('nothing to download');
    }
    session.paused = false;
    if (DownloadRepository.running.indexOf(videoId) < 0) {
      DownloadRepository.running.push(videoId);
    }
    DownloadRepository.setProgress(videoId, DownloadRepository.snapshot(session, false));
    try {
      return await DownloadRepository.runLoop(session);
    } catch (e) {
      const error = e as Error;
      // A pause or a cancel is not a failure; anything else leaves what was
      // fetched in place and offers the download back as resumable.
      if (error.message !== 'paused' && error.message !== 'cancelled') {
        session.paused = true;
        DownloadRepository.setProgress(videoId, DownloadRepository.snapshot(session, true));
      }
      throw error;
    } finally {
      const wasCancelled: boolean = DownloadRepository.cancelled.indexOf(videoId) >= 0;
      DownloadRepository.running = DownloadRepository.running.filter((id: string) => id !== videoId);
      DownloadRepository.cancelled = DownloadRepository.cancelled.filter((id: string) => id !== videoId);
      if (wasCancelled) {
        // A cancelled download kept nothing, so it is not a download: the row
        // goes with the partial file.
        const record: DownloadEntry | undefined = DownloadRepository.find(videoId);
        if (record !== undefined && !record.downloaded) {
          DownloadRepository.remove(videoId);
        }
      }
      if (session.finished || wasCancelled) {
        DownloadRepository.sessions.delete(videoId);
        DownloadRepository.setProgress(videoId, undefined);
      }
    }
  }

  /**
   * Asks for a data-transfer continuous task, so the transfer is not frozen when
   * the app leaves the foreground.
   *
   * Not stopping it again is deliberate: the continuous task is per process, and
   * playback usually holds the audio one - stopping that to tidy up a download
   * would get a playing stream killed. It ends with the process either way.
   */
  private static async beginBackgroundTask(context: common.UIAbilityContext): Promise<void> {
    try {
      const want: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      };
      const info: wantAgent.WantAgentInfo = {
        wants: [want],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      hilog.info(DOMAIN, TAG, 'background transfer task started');
    } catch (e) {
      // Without the task the download still runs while the app is in front.
      hilog.warn(DOMAIN, TAG, 'no background task (%{public}s)', JSON.stringify(e));
    }
  }

  private static setProgress(videoId: string, progress: DownloadProgress | undefined): void {
    if (progress === undefined) {
      DownloadRepository.progress.delete(videoId);
    } else {
      DownloadRepository.progress.set(videoId, progress);
    }
    DownloadRepository.bump();
  }

  /** Tells every page watching the downloads that something has changed. */
  private static bump(): void {
    const current: number = AppStorage.get<number>(DownloadRepository.KEY_DOWNLOAD_VERSION) ?? 0;
    AppStorage.setOrCreate(DownloadRepository.KEY_DOWNLOAD_VERSION, current + 1);
  }

  /**
   * Transfers the media, then the comments, then records the result.
   *
   * Appending rather than rewriting is what makes a resume work: the file already
   * holds everything up to `index`, so the loop carries on from there.
   */
  private static async runLoop(session: DownloadSession): Promise<string> {
    if (!session.videoDone) {
      if (session.parts.length === 0) {
        const opened: boolean = await DownloadRepository.openSource(session);
        if (!opened) {
          throw new Error('no rendition could be downloaded');
        }
      }
      const file = fs.openSync(session.filePath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      try {
        while (session.index < session.parts.length) {
          if (DownloadRepository.cancelled.indexOf(session.videoId) >= 0) {
            throw new Error('cancelled');
          }
          if (session.paused) {
            throw new Error('paused');
          }
          const started: number = Date.now();
          const buffer: ArrayBuffer | undefined =
            await Http.requestBuffer(session.parts[session.index], {});
          if (buffer === undefined) {
            throw new Error(`segment ${session.index} could not be downloaded`);
          }
          fs.writeSync(file.fd, buffer);
          session.bytes += buffer.byteLength;
          const elapsedMs: number = Math.max(1, Date.now() - started);
          const instant: number = buffer.byteLength / (elapsedMs / 1000);
          // Smoothed, so the number shown does not jump between segments.
          session.bytesPerSecond = session.bytesPerSecond > 0
            ? session.bytesPerSecond * 0.5 + instant * 0.5 : instant;
          session.index++;
          DownloadRepository.setProgress(session.videoId, DownloadRepository.snapshot(session, false));
        }
      } catch (e) {
        fs.closeSync(file);
        const error = e as Error;
        if (error.message === 'cancelled') {
          // A cancelled download keeps nothing: the partial file is worthless on
          // its own, and the queue would only be in the way of a fresh start.
          DownloadRepository.deleteFile(session.filePath);
          DownloadRepository.deleteFile(CommentRepository.pathFor(session.filePath));
          session.parts = [];
          session.index = 0;
          session.bytes = 0;
          session.filePath = '';
        }
        throw error;
      }
      fs.closeSync(file);
      session.videoDone = true;
    }

    session.phase = PHASE_COMMENTS;
    DownloadRepository.setProgress(session.videoId, DownloadRepository.snapshot(session, false));
    await DownloadRepository.downloadComments(session);

    DownloadRepository.attachDownload(session.videoId, session.filePath, session.audioOnly);
    session.finished = true;
    hilog.info(DOMAIN, TAG, 'download complete for %{public}s', session.videoId);
    return session.filePath;
  }

  /**
   * The chat replay of the video, stored beside it.
   *
   * A failure here does not fail the download: the media is the point, and a
   * replay that could not be fetched should not throw away a finished file.
   */
  private static async downloadComments(session: DownloadSession): Promise<void> {
    try {
      const messages: ChatMessage[] = await CommentRepository.fetchAll(session.videoId,
        (pages: number): void => {
          hilog.debug(DOMAIN, TAG, 'comment page %{public}d', pages);
        });
      if (messages.length === 0) {
        return;
      }
      CommentRepository.save(session.filePath, messages);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not store the comments: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * Picks the first candidate whose playlist can actually be read and opens it.
   *
   * A candidate that will not read is skipped rather than fatal: the usher master
   * is unreachable on some devices while the CDN links derived from the storyboard
   * answer fine, and the transfer should not care which of the two it used.
   *
   * Which candidate may be used depends on who chose it. When the user picked a
   * rendition in the sheet, only that quality is tried - the two URLs a quality can
   * have are alternatives, two qualities are not - and if neither answers the
   * download fails instead of quietly fetching something else. Only an automatic
   * download is free to settle for whatever the source will give it.
   */
  private static async openSource(session: DownloadSession): Promise<boolean> {
    const wanted: string = session.picked;
    let usable: Quality[] = DownloadRepository.usable(session.candidates);
    if (wanted.length > 0) {
      usable = DownloadRepository.named(usable, wanted);
    }
    if (usable.length === 0) {
      const master: Quality[] = await DownloadRepository.fromMaster(session.videoId);
      if (wanted.length > 0) {
        usable = DownloadRepository.named(master, wanted);
      } else {
        const best: Quality | undefined = DownloadRepository.pickRendition(master);
        usable = best !== undefined ? [best] : [];
      }
    }

    let failure: string = '';
    for (let i = 0; i < usable.length; i++) {
      const target: Quality = usable[i];
      const playlist: string = await Http.requestText(target.url, {});
      if (playlist.length === 0) {
        failure = `${target.name}: the playlist could not be read`;
        hilog.warn(DOMAIN, TAG, '%{public}s', failure);
        continue;
      }
      const map: string = DownloadRepository.mapUri(playlist, target.url);
      const parts: string[] = DownloadRepository.partUris(playlist, target.url, map);
      if (parts.length === 0) {
        failure = `${target.name}: the rendition has no segments`;
        hilog.warn(DOMAIN, TAG, '%{public}s', failure);
        continue;
      }
      const directory: string = `${session.baseDir}/downloads`;
      if (!fs.accessSync(directory)) {
        fs.mkdirSync(directory);
      }
      session.target = target;
      session.audioOnly = target.isAudioOnly;
      // A file left behind by an earlier download of this video is replaced, never
      // appended to: the segments are fetched from the first one again, so
      // appending would silently double the file.
      const path: string = `${directory}/${session.videoId}.${DownloadRepository.extension(map, parts[0])}`;
      DownloadRepository.discard(session.videoId, path);
      session.filePath = path;
      session.parts = parts;
      session.index = 0;
      session.bytes = 0;
      // The playlist says how long the stream really is, which is a better total
      // than the length the metadata claims; the bitrate times it is the size the
      // progress bar scales against. Without either, the estimate is only that.
      const seconds: number = DownloadRepository.playlistDuration(playlist);
      const duration: number = seconds > 0 ? seconds : session.durationSeconds;
      const bitrate: number = DownloadRepository.bitrate(target);
      session.totalBytes = Math.max(0, Math.floor(bitrate / 8 * duration));
      hilog.info(DOMAIN, TAG, 'downloading %{public}s at %{public}s (%{public}d parts)',
        session.videoId, target.name, parts.length);
      return true;
    }
    throw new Error(failure.length > 0 ? failure : 'no rendition could be downloaded');
  }

  /** What the UI shows for a session, right now. */
  private static snapshot(session: DownloadSession, paused: boolean): DownloadProgress {
    const progress: DownloadProgress = new DownloadProgress(
      session.phase === PHASE_COMMENTS ? 100 : DownloadRepository.percent(session.bytes, session.totalBytes),
      session.bytes, session.totalBytes, session.index, session.parts.length);
    progress.bytesPerSecond = session.bytesPerSecond;
    progress.paused = paused;
    progress.phase = session.phase;
    progress.audioOnly = session.audioOnly;
    progress.videoId = session.videoId;
    return progress;
  }

  /** Every rendition the usher master lists, when that request does work. */
  private static async fromMaster(videoId: string): Promise<Quality[]> {
    const token: PlaybackToken | undefined = await PlaybackRepository.accessToken(videoId);
    const masterUrl: string = PlaybackRepository.buildVodUrl(videoId, token);
    const master: string = await Http.requestText(masterUrl, PlaybackRepository.usherHeaders());
    if (master.length === 0) {
      return [];
    }
    return HlsParser.parseMaster(master, masterUrl);
  }

  /** The candidates of one quality, whichever URLs they carry. */
  private static named(candidates: Quality[], name: string): Quality[] {
    const result: Quality[] = [];
    for (let i = 0; i < candidates.length; i++) {
      if (candidates[i].name === name) {
        result.push(candidates[i]);
      }
    }
    return result;
  }

  /**
   * Real duration of the media the playlist lists, in seconds.
   *
   * The sum of the segment durations is what the file will actually hold, which
   * is more trustworthy than the length the video's metadata reports - the two
   * differ on a stream that was cut short or on a highlight.
   */
  private static playlistDuration(playlist: string): number {
    const lines: string[] = playlist.split('\n');
    let seconds: number = 0;
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (!line.startsWith('#EXTINF:')) {
        continue;
      }
      const value: number = Number.parseFloat(line.substring(8));
      if (!Number.isNaN(value) && value > 0 && value < 3600) {
        seconds += value;
      }
    }
    return seconds;
  }

  /** Bits per second of a rendition, as told or as guessed from its name. */
  private static bitrate(quality: Quality): number {
    return quality.bandwidth > 0
      ? quality.bandwidth : DownloadRepository.nominalBitrate(quality.name);
  }

  /** Candidates that can actually be opened, without repeats. */
  private static usable(candidates: Quality[]): Quality[] {
    const result: Quality[] = [];
    const seen: string[] = [];
    for (let i = 0; i < candidates.length; i++) {
      const quality: Quality = candidates[i];
      // Audio-only renditions are wanted here: they are a deliberate choice for
      // music and talk, and they are the smallest thing to keep.
      if (quality.url.length === 0 || seen.indexOf(quality.url) >= 0) {
        continue;
      }
      seen.push(quality.url);
      result.push(quality);
    }
    return result;
  }

  private static percent(bytes: number, totalBytes: number): number {
    if (totalBytes <= 0) {
      return 0;
    }
    const percent: number = Math.floor(bytes / totalBytes * 100);
    return percent > 100 ? 100 : percent;
  }

  /**
   * The rendition to download: the best one at or below MAX_HEIGHT, or the
   * smallest available when the stream never offers anything that low.
   */
  private static pickRendition(qualities: Quality[]): Quality | undefined {
    let best: Quality | undefined = undefined;
    let smallest: Quality | undefined = undefined;
    let smallestBandwidth: number = -1;
    for (let i = 0; i < qualities.length; i++) {
      const quality: Quality = qualities[i];
      if (quality.isAudioOnly || quality.url.length === 0) {
        continue;
      }
      const height: number = DownloadRepository.height(quality.resolution);
      if (height > 0 && height <= MAX_HEIGHT && (best === undefined || quality.bandwidth > best.bandwidth)) {
        best = quality;
      }
      if (smallestBandwidth < 0 || quality.bandwidth < smallestBandwidth) {
        smallestBandwidth = quality.bandwidth;
        smallest = quality;
      }
    }
    return best !== undefined ? best : smallest;
  }

  /** Height of a "1280x720" resolution string, or 0 when it has none. */
  private static height(resolution: string): number {
    const x: number = resolution.indexOf('x');
    if (x <= 0) {
      return 0;
    }
    const parsed: number = Number.parseInt(resolution.substring(x + 1), 10);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  /** Initialisation segment of an EXT-X-MAP playlist, as a full URL. */
  private static mapUri(playlist: string, baseUrl: string): string {
    const lines: string[] = playlist.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (!line.startsWith('#EXT-X-MAP:')) {
        continue;
      }
      const marker: number = line.indexOf('URI="');
      if (marker < 0) {
        continue;
      }
      const rest: string = line.substring(marker + 5);
      const end: number = rest.indexOf('"');
      if (end < 0) {
        continue;
      }
      return HlsParser.resolveUrl(rest.substring(0, end), baseUrl);
    }
    return '';
  }

  /** Segment URLs in playlist order, with the init segment first when there is one. */
  private static partUris(playlist: string, baseUrl: string, map: string): string[] {
    const lines: string[] = playlist.split('\n');
    const urls: string[] = [];
    if (map.length > 0) {
      urls.push(map);
    }
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0 || line.startsWith('#')) {
        continue;
      }
      urls.push(HlsParser.resolveUrl(line, baseUrl));
    }
    return urls;
  }

  private static extension(map: string, firstPart: string): string {
    if (map.length > 0) {
      return 'mp4';
    }
    const query: number = firstPart.indexOf('?');
    const clean: string = query > 0 ? firstPart.substring(0, query) : firstPart;
    return clean.endsWith('.m4s') || clean.endsWith('.mp4') ? 'mp4' : 'ts';
  }

  private static deleteFile(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not remove the partial file');
    }
  }
}
