import 'package:media_kit/media_kit.dart';

/// `demuxer-lavf-o` shared by the embedded player and the system mpv.
///
/// media_kit always appends `strict=experimental`, which switches on ffmpeg's
/// unfinished `EXT-X-MEDIA` handling. An HLS master that advertises a subtitle
/// rendition (ErsatzTV publishes a `DEFAULT=YES` WebVTT one) then makes ffmpeg
/// attach the subtitle playlist to the variant and read `.vtt` segments only,
/// so no video or audio packet ever arrives. Keeping media_kit's other options
/// but dropping the experimental flag lets ffmpeg ignore the rendition and
/// stay on the video playlist.
final String kMpvDemuxerLavfOptions = <String>[
  'seg_max_retry=5',
  'allowed_extensions=ALL',
  'protocol_whitelist=[${const PlayerConfiguration().protocolWhitelist.join(',')}]',
].join(',');
