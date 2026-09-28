/** The signed-in Twitch account. */
export class TwitchUser {
  id: string = '';
  login: string = '';
  displayName: string = '';
  profileImageURL: string = '';

  static empty(): TwitchUser {
    return new TwitchUser();
  }
}
