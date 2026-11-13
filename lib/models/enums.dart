// KONTRAK DATAWISE v1.0. Perubahan enum harus melalui review arsitek.
enum UsageSource { auto, manual }
enum UsageReadStatus { ok, permissionDenied, unsupported, error }
enum PlannerStatus { normal, notStarted, depleted, expired }
enum AlertType { daily80, daily100, dailyOver, quota10, expiring1d }
enum QuotaCategoryType { main, night, social, app, custom }
