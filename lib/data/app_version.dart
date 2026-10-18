/// Une version `majeure.mineure.corrigée[+build]`, comparable.
///
/// Deux vocabulaires se rencontrent ici : `pubspec.yaml` écrit `1.0.1+14`
/// (Flutter en fait `versionName` et `versionCode`), GitHub nomme ses tags
/// `v1.0.1`. Ce type est la seule traduction entre les deux, et il refuse tout
/// ce qui ne ressemble pas exactement à l'un ou à l'autre — un tag `nightly`
/// ou `v1.0-beta` ne devient pas une version qu'on proposerait à quelqu'un.
///
/// Le numéro de build compte : Android s'en sert pour décider qu'un APK peut
/// remplacer l'installé, et deux builds d'une même version ne sont pas
/// interchangeables. Un tag GitHub n'en porte pas (il vaut alors 0), donc publier
/// `v1.0.1` après un `1.0.1+3` ne propose rien — c'est voulu : seule une
/// version plus haute se propose.
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;

  /// `versionCode` Android / `CFBundleVersion` iOS. 0 quand la source n'en dit
  /// rien (tag GitHub).
  final int build;

  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  /// `v1.0.1`, `1.0.1`, `1.0.1+14` → une version ; tout le reste → null.
  static final RegExp _pattern =
      RegExp(r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');

  static AppVersion? tryParse(String raw) {
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    final build = int.tryParse(match.group(4) ?? '0');
    if (major == null || minor == null || patch == null || build == null) {
      return null;
    }
    return AppVersion(major, minor, patch, build);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);

  /// `1.0.1` — le build n'apparaît que s'il existe, sinon « 1.0.1+0 » se lirait
  /// comme une précision qui n'a pas été publiée.
  @override
  String toString() => build > 0
      ? '$major.$minor.$patch+$build'
      : '$major.$minor.$patch';
}
