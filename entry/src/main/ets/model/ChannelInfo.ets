import { Stream } from './Stream';

/**
 * The channel page's own data, from Xtra's UserChannelPage.graphql: identity,
 * follower count, and the live broadcast when there is one.
 *
 * `live` is only meaningful while `isLive`; the rest of the app treats "live" as
 * a state that can flip at any time, so it is a flag plus a value rather than an
 * optional field every caller has to unwrap.
 */
export class ChannelInfo {
  id: string = '';
  login: string = '';
  displayName: string = '';
  profileImageURL: string = '';
  followerCount: number = 0;
  lastBroadcastAt: string = '';
  isLive: boolean = false;
  live: Stream = new Stream();
}
