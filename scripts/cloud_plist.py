# 只将已注册的公开OAuth客户端标识写入安装包。
from head import Path, UUID, argv, fullmatch, loads, pl_dumps


def configure(source, output, clients):
    info = loads(Path(source).read_bytes())
    overrides = loads(Path(clients).read_bytes()) if clients else {}
    google = overrides.get("GoogleDriveClientID", info.get("GoogleDriveClientID", ""))
    microsoft = overrides.get("OneDriveClientID", info.get("OneDriveClientID", ""))
    if google:
        if not isinstance(google, str) or not fullmatch(r"[a-zA-Z0-9-]+\.apps\.googleusercontent\.com", google):
            raise ValueError("GoogleDriveClientID必须是已注册的iOS客户端ID")
        scheme = ".".join(reversed(google.split(".")))
        entries = info.setdefault("CFBundleURLTypes", [])
        if not any(scheme in item.get("CFBundleURLSchemes", []) for item in entries):
            entries.append({"CFBundleURLSchemes": [scheme]})
    if microsoft and (not isinstance(microsoft, str) or str(UUID(microsoft)) != microsoft.lower()):
        raise ValueError("OneDriveClientID必须是Microsoft Entra应用ID")
    info["GoogleDriveClientID"] = google
    info["OneDriveClientID"] = microsoft
    data = pl_dumps(info, sort_keys=False)
    dest = Path(output)
    if not dest.exists() or dest.read_bytes() != data:
        dest.write_bytes(data)


if __name__ == "__main__":
    configure(*argv[1:])
