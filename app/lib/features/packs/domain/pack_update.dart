/// True when a newer version of an installed pack is listed.
/// A pack that is not installed has no update, it needs a first install.
bool isUpdateAvailable({required int? installedVersion, required int listedVersion}) =>
    installedVersion != null && listedVersion > installedVersion;
