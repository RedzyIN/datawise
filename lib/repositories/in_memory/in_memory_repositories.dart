import '../../models/models.dart';
import '../alert_repository.dart';
import '../classification_rule_repository.dart';
import '../data_limit_repository.dart';
import '../package_repository.dart';
import '../quota_category_repository.dart';
import '../settings_repository.dart';
import '../usage_repository.dart';

class InMemoryPackageRepository implements PackageRepository {
  final Map<int,DataPackage> _items={}; final List<void Function(int)> _listeners=[]; int _next=1;
  void addDeleteListener(void Function(int) f)=>_listeners.add(f);
  void _deactivate(String uid,int except){for(final e in _items.entries.toList()){if(e.value.userId==uid&&e.key!=except)_items[e.key]=e.value.copyWith(isActive:false);}}
  @override Future<int> add(DataPackage p) async {if(p.totalBytes<=0||p.initialUsedBytes<0||!p.endDate.isAfter(p.startDate))throw const AppException(AppException.validation,'Data paket tidak valid.');final id=_next++;if(p.isActive)_deactivate(p.userId,id);_items[id]=p.copyWith(id:id);return id;}
  @override Future<void> update(DataPackage p) async {final id=p.id;if(id==null||!_items.containsKey(id))throw const AppException(AppException.notFound,'Paket tidak ditemukan.');if(p.totalBytes<=0||p.initialUsedBytes<0||!p.endDate.isAfter(p.startDate))throw const AppException(AppException.validation,'Data paket tidak valid.');if(p.isActive)_deactivate(p.userId,id);_items[id]=p;}
  @override Future<void> delete(int id) async {if(_items.remove(id)==null)throw const AppException(AppException.notFound,'Paket tidak ditemukan.');for(final f in _listeners){f(id);}}
  @override Future<DataPackage?> getById(int id) async=>_items[id];
  @override Future<DataPackage?> getActive(String uid) async=>_items.values.where((p)=>p.userId==uid&&p.isActive).firstOrNull;
  @override Future<List<DataPackage>> getAll(String uid) async {final a=_items.values.where((p)=>p.userId==uid).toList()..sort((x,y){final c=y.createdAt.compareTo(x.createdAt);return c!=0?c:(y.id??0).compareTo(x.id??0);});return a;}
  @override Future<void> setActive(String uid,int id) async {final p=_items[id];if(p==null||p.userId!=uid)throw const AppException(AppException.notFound,'Paket tidak ditemukan.');for(final e in _items.entries.toList()){if(e.value.userId==uid)_items[e.key]=e.value.copyWith(isActive:e.key==id);}}
}

class InMemoryQuotaCategoryRepository implements QuotaCategoryRepository {
  InMemoryQuotaCategoryRepository(this.packages){packages.addDeleteListener((id)=>items.removeWhere((_,v)=>v.packageId==id));}
  final InMemoryPackageRepository packages; final Map<int,QuotaCategory> items={}; int next=1;
  final List<void Function(int)> _categoryDeleteListeners=[];
  void addDeleteListener(void Function(int) listener)=>_categoryDeleteListeners.add(listener);
  @override Future<int> add(QuotaCategory c) async {if(await packages.getById(c.packageId)==null||c.quotaBytes<=0)throw const AppException(AppException.validation,'Kategori tidak valid.');if(items.values.any((v)=>v.packageId==c.packageId&&(v.name==c.name||(c.type==QuotaCategoryType.main&&v.type==QuotaCategoryType.main))))throw const AppException(AppException.validation,'Nama atau kategori utama sudah digunakan.');final id=next++;items[id]=QuotaCategory(id:id,packageId:c.packageId,name:c.name,type:c.type,quotaBytes:c.quotaBytes,startMinute:c.startMinute,endMinute:c.endMinute,createdAt:c.createdAt,updatedAt:c.updatedAt);return id;}
  @override Future<void> update(QuotaCategory c) async {if(c.id==null||!items.containsKey(c.id))throw const AppException(AppException.notFound,'Kategori tidak ditemukan.');items[c.id!]=c;}
  @override Future<void> delete(int id) async {if(items.remove(id)==null)throw const AppException(AppException.notFound,'Kategori tidak ditemukan.');for(final f in _categoryDeleteListeners){f(id);}}
  @override Future<QuotaCategory?> getById(int id) async=>items[id];
  @override Future<List<QuotaCategory>> getByPackage(int id) async=>items.values.where((v)=>v.packageId==id).toList();
}

class InMemoryClassificationRuleRepository implements ClassificationRuleRepository {
  InMemoryClassificationRuleRepository(this.packages,this.categories){
    packages.addDeleteListener((id)=>items.removeWhere((_,v)=>v.packageId==id));
    categories.addDeleteListener((id)=>items.removeWhere((_,v)=>v.categoryId==id));
  }
  final InMemoryPackageRepository packages;final InMemoryQuotaCategoryRepository categories;
  final Map<int,ClassificationRule> items={};int next=1;
  @override Future<int> add(ClassificationRule r) async {final category=await categories.getById(r.categoryId);if(await packages.getById(r.packageId)==null||category==null||category.packageId!=r.packageId||r.appPackageName.trim().isEmpty)throw const AppException(AppException.validation,'Aturan klasifikasi tidak valid.');final id=next++;items[id]=ClassificationRule(id:id,packageId:r.packageId,categoryId:r.categoryId,appPackageName:r.appPackageName,startMinute:r.startMinute,endMinute:r.endMinute,priority:r.priority,isEnabled:r.isEnabled,createdAt:r.createdAt,updatedAt:r.updatedAt);return id;}
  @override Future<void> update(ClassificationRule r) async {if(r.id==null||!items.containsKey(r.id))throw const AppException(AppException.notFound,'Aturan tidak ditemukan.');items[r.id!]=r;}
  @override Future<void> delete(int id) async {if(items.remove(id)==null)throw const AppException(AppException.notFound,'Aturan tidak ditemukan.');}
  @override Future<List<ClassificationRule>> getByPackage(int id) async {final a=items.values.where((v)=>v.packageId==id).toList()..sort((x,y)=>x.priority!=y.priority?x.priority.compareTo(y.priority):(x.id??0).compareTo(y.id??0));return a;}
}

class InMemoryUsageRepository implements UsageRepository {
  InMemoryUsageRepository(this.packages,[this.categories]){
    packages.addDeleteListener((id){final ids=records.values.where((r)=>r.packageId==id).map((r)=>r.id).toSet();records.removeWhere((_,r)=>r.packageId==id);allocations.removeWhere((_,a)=>ids.contains(a.usageRecordId));});
    categories?.addDeleteListener((id)=>allocations.removeWhere((_,a)=>a.categoryId==id));
  }
  final InMemoryPackageRepository packages;final InMemoryQuotaCategoryRepository? categories;final Map<int,UsageRecord> records={};final Map<int,UsageAllocation> allocations={};int nextRecord=1,nextAllocation=1;
  @override Future<void> upsertRecord(int pid,DateTime date,int bytes,UsageSource source) async {if(await packages.getById(pid)==null)throw const AppException(AppException.notFound,'Paket tidak ditemukan.');if(bytes<0)throw const AppException(AppException.validation,'Pemakaian tidak boleh negatif.');final d=dateOnly(date);final old=records.values.where((r)=>r.packageId==pid&&dateOnly(r.recordDate)==d&&r.source==source).firstOrNull;final id=old?.id??nextRecord++;records[id]=UsageRecord(id:id,packageId:pid,recordDate:d,usedBytes:bytes,source:source,updatedAt:DateTime.now());allocations.removeWhere((_,a)=>a.usageRecordId==id);}
  @override Future<void> deleteManual(int pid,DateTime date) async {final d=dateOnly(date);final ids=records.values.where((r)=>r.packageId==pid&&dateOnly(r.recordDate)==d&&r.source==UsageSource.manual).map((r)=>r.id).toSet();records.removeWhere((_,r)=>ids.contains(r.id));allocations.removeWhere((_,a)=>ids.contains(a.usageRecordId));}
  @override Future<UsageRecord?> getEffectiveRecord(int pid,DateTime date) async {final d=dateOnly(date);final a=records.values.where((r)=>r.packageId==pid&&dateOnly(r.recordDate)==d);return a.where((r)=>r.source==UsageSource.manual).firstOrNull??a.where((r)=>r.source==UsageSource.auto).firstOrNull;}
  @override Future<List<UsageRecord>> getEffectiveRecords(int pid) async {final dates=records.values.where((r)=>r.packageId==pid).map((r)=>dateOnly(r.recordDate)).toSet();final out=<UsageRecord>[];for(final d in dates){final r=await getEffectiveRecord(pid,d);if(r!=null)out.add(r);}out.sort((a,b)=>a.recordDate.compareTo(b.recordDate));return out;}
  @override Future<List<UsageRecord>> getRecords(int pid) async=>records.values.where((r)=>r.packageId==pid).toList();
  @override Future<int> getUsedBytesOn(int pid,DateTime d) async=>(await getEffectiveRecord(pid,d))?.usedBytes??0;
  @override Future<int> getTotalUsedBytes(int pid) async {final p=await packages.getById(pid);if(p==null)throw const AppException(AppException.notFound,'Paket tidak ditemukan.');return p.initialUsedBytes+(await getEffectiveRecords(pid)).fold<int>(0,(s,r)=>s+r.usedBytes);}
  @override Future<Map<DateTime,int>> getDailyUsage(int pid) async {final out=<DateTime,int>{};for(final r in await getEffectiveRecords(pid)){out[dateOnly(r.recordDate)]=r.usedBytes;}return out;}
  @override Future<void> replaceAllocations(int rid,List<UsageAllocation> rows) async {final r=records[rid];if(r==null)throw const AppException(AppException.notFound,'Catatan pemakaian tidak ditemukan.');final total=rows.fold<int>(0,(s,a)=>s+a.usedBytes);if(rows.any((a)=>a.usedBytes<0)||total>r.usedBytes)throw const AppException(AppException.validation,'Total alokasi melebihi pemakaian record.');
    if(rows.map((a)=>'${a.categoryId}|${a.appPackageName}').toSet().length!=rows.length)throw const AppException(AppException.validation,'Alokasi duplikat.');
    if(categories!=null){for(final a in rows){final category=await categories!.getById(a.categoryId);if(category==null||category.packageId!=r.packageId)throw const AppException(AppException.validation,'Kategori alokasi tidak sesuai dengan paket.');}}allocations.removeWhere((_,a)=>a.usageRecordId==rid);for(final a in rows){final id=nextAllocation++;allocations[id]=UsageAllocation(id:id,usageRecordId:rid,categoryId:a.categoryId,appPackageName:a.appPackageName,usedBytes:a.usedBytes);}}
  @override Future<List<UsageAllocation>> getAllocations(int id) async=>allocations.values.where((a)=>a.usageRecordId==id).toList();
  @override Future<Map<int,int>> getCategoryUsage(int pid) async {final ids=(await getEffectiveRecords(pid)).map((r)=>r.id).toSet();final out=<int,int>{};for(final a in allocations.values.where((a)=>ids.contains(a.usageRecordId))){out[a.categoryId]=(out[a.categoryId]??0)+a.usedBytes;}return out;}
}

class InMemoryDataLimitRepository implements DataLimitRepository {
  InMemoryDataLimitRepository(this.packages){packages.addDeleteListener((id)=>items.remove(id));}
  final InMemoryPackageRepository packages;final Map<int,DataLimitSetting> items={};
  @override Future<DataLimitSetting?> getByPackage(int id) async=>items[id];
  @override Future<void> upsert(DataLimitSetting s) async {if(await packages.getById(s.packageId)==null)throw const AppException(AppException.notFound,'Paket tidak ditemukan.');if(s.dailyWarningPercent<=0||s.quotaWarningPercent<1||s.quotaWarningPercent>100)throw const AppException(AppException.validation,'Pengaturan batas tidak valid.');items[s.packageId]=s;}
}

class InMemoryAlertRepository implements AlertRepository {
  InMemoryAlertRepository(this.packages){packages.addDeleteListener((id)=>logs.removeWhere((_,v)=>v.packageId==id));}
  final InMemoryPackageRepository packages;final Map<String,AlertLog> logs={};
  String key(int id,AlertType t,DateTime d)=>'$id|${t.name}|${dateToDb(d)}';
  @override Future<bool> hasBeenSent(int id,AlertType t,DateTime d) async=>logs.containsKey(key(id,t,d));
  @override Future<void> markSent(int id,AlertType t,DateTime d) async {final k=key(id,t,d);logs.putIfAbsent(k,()=>AlertLog(packageId:id,type:t,alertDate:dateOnly(d),sentAt:DateTime.now()));}
  @override Future<List<AlertLog>> getByPackage(int id) async=>logs.values.where((v)=>v.packageId==id).toList();
}

class InMemorySettingsRepository implements SettingsRepository {
  final Map<String,String> items={};String key(String uid,String k)=>'$uid|$k';
  @override Future<String?> get(String uid,String k) async=>items[key(uid,k)];
  @override Future<void> set(String uid,String k,String v) async=>items[key(uid,k)]=v;
  @override Future<void> delete(String uid,String k) async=>items.remove(key(uid,k));
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
