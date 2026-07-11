import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/knowledge_base.dart';
import '../services/api_service.dart';

/// State for the Knowledge Base feature: the list of KBs, the selected KB's
/// documents, and live ingestion-job polling after uploads.
class KbProvider extends ChangeNotifier {
  List<KnowledgeBase> _kbs = [];
  bool _loading = false;
  String? _error;

  KnowledgeBase? _selected;
  List<KbDocument> _documents = [];
  bool _documentsLoading = false;

  // docId → latest ingestion job (drives per-document progress bars).
  final Map<int, IngestionJob> _jobs = {};
  final Set<int> _polling = {};

  List<KnowledgeBase> get knowledgeBases => _kbs;
  bool get loading => _loading;
  String? get error => _error;
  KnowledgeBase? get selected => _selected;
  List<KbDocument> get documents => _documents;
  bool get documentsLoading => _documentsLoading;
  IngestionJob? jobFor(int docId) => _jobs[docId];
  bool get anyIngesting => _documents.any((d) => d.isBusy);

  Future<void> loadKnowledgeBases() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _kbs = await ApiService.listKnowledgeBases();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<KnowledgeBase> createKnowledgeBase(String name, {String? description}) async {
    final kb = await ApiService.createKnowledgeBase(name, description: description);
    _kbs = [kb, ..._kbs];
    notifyListeners();
    return kb;
  }

  Future<void> renameKnowledgeBase(int id, {String? name, String? description}) async {
    await ApiService.updateKnowledgeBase(id, name: name, description: description);
    await loadKnowledgeBases();
    if (_selected?.id == id) {
      _selected = _kbs.firstWhere((k) => k.id == id, orElse: () => _selected!);
      notifyListeners();
    }
  }

  Future<void> deleteKnowledgeBase(int id) async {
    await ApiService.deleteKnowledgeBase(id);
    _kbs = _kbs.where((k) => k.id != id).toList();
    if (_selected?.id == id) {
      _selected = null;
      _documents = [];
    }
    notifyListeners();
  }

  Future<void> selectKnowledgeBase(KnowledgeBase kb) async {
    _selected = kb;
    _documents = [];
    notifyListeners();
    await loadDocuments();
  }

  void clearSelection() {
    _selected = null;
    _documents = [];
    notifyListeners();
  }

  Future<void> loadDocuments() async {
    final kb = _selected;
    if (kb == null) return;
    _documentsLoading = true;
    notifyListeners();
    try {
      _documents = await ApiService.listDocuments(kb.id);
      // Resume polling for anything still in-flight (e.g. after reopening).
      for (final d in _documents) {
        if (d.isBusy) _startPolling(kb.id, d.id);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _documentsLoading = false;
      notifyListeners();
    }
  }

  /// Refresh the selected KB's aggregate stats (chunk count, embedding label).
  Future<void> _refreshSelectedKb() async {
    final kb = _selected;
    if (kb == null) return;
    try {
      final fresh = await ApiService.getKnowledgeBase(kb.id);
      _selected = fresh;
      _kbs = _kbs.map((k) => k.id == fresh.id ? fresh : k).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> uploadDocument(String filename, List<int> bytes) async {
    final kb = _selected;
    if (kb == null) return;
    final resp = await ApiService.uploadDocument(kb.id, filename, bytes);
    final doc = KbDocument.fromJson(resp['document'] as Map<String, dynamic>);
    _documents = [doc, ..._documents];
    notifyListeners();
    _startPolling(kb.id, doc.id);
  }

  void _startPolling(int kbId, int docId) {
    if (_polling.contains(docId)) return;
    _polling.add(docId);
    _pollLoop(kbId, docId);
  }

  Future<void> _pollLoop(int kbId, int docId) async {
    try {
      for (var i = 0; i < 400; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1400));
        if (_selected?.id != kbId) break; // user navigated away
        IngestionJob job;
        try {
          job = await ApiService.getDocumentJob(kbId, docId);
        } catch (_) {
          continue;
        }
        _jobs[docId] = job;
        notifyListeners();
        if (job.isTerminal) {
          await loadDocuments();      // refresh statuses
          await _refreshSelectedKb(); // refresh chunk count / embedding label
          break;
        }
      }
    } finally {
      _polling.remove(docId);
    }
  }

  Future<void> deleteDocument(int docId) async {
    final kb = _selected;
    if (kb == null) return;
    await ApiService.deleteDocument(kb.id, docId);
    _documents = _documents.where((d) => d.id != docId).toList();
    _jobs.remove(docId);
    notifyListeners();
    await _refreshSelectedKb();
  }

  Future<void> reingestDocument(int docId) async {
    final kb = _selected;
    if (kb == null) return;
    await ApiService.reingestDocument(kb.id, docId);
    await loadDocuments();
    _startPolling(kb.id, docId);
  }
}
