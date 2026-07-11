// Client models for the Knowledge Base (RAG) feature. Field names mirror the
// backend DTOs in `schemas.py`.

class KnowledgeBase {
  final int id;
  final String name;
  final String? description;
  final String? embeddingPlatform;
  final String? embeddingModel;
  final int? embeddingDim;
  final int documentCount;
  final int chunkCount;

  KnowledgeBase({
    required this.id,
    required this.name,
    this.description,
    this.embeddingPlatform,
    this.embeddingModel,
    this.embeddingDim,
    this.documentCount = 0,
    this.chunkCount = 0,
  });

  factory KnowledgeBase.fromJson(Map<String, dynamic> j) => KnowledgeBase(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        description: j['description'] as String?,
        embeddingPlatform: j['embedding_platform'] as String?,
        embeddingModel: j['embedding_model'] as String?,
        embeddingDim: j['embedding_dim'] as int?,
        documentCount: (j['document_count'] ?? 0) as int,
        chunkCount: (j['chunk_count'] ?? 0) as int,
      );

  /// Human label for the embedding model this KB is pinned to (once ingested).
  String? get embeddingLabel =>
      embeddingModel == null ? null : '$embeddingModel${embeddingDim != null ? ' · ${embeddingDim}d' : ''}';
}

class KbDocument {
  final int id;
  final int knowledgeBaseId;
  final String filename;
  final String? contentType;
  final int? sizeBytes;
  final String status; // pending, processing, completed, failed
  final String? error;
  final int chunkCount;

  KbDocument({
    required this.id,
    required this.knowledgeBaseId,
    required this.filename,
    this.contentType,
    this.sizeBytes,
    required this.status,
    this.error,
    this.chunkCount = 0,
  });

  factory KbDocument.fromJson(Map<String, dynamic> j) => KbDocument(
        id: j['id'] as int,
        knowledgeBaseId: j['knowledge_base_id'] as int,
        filename: (j['filename'] ?? 'document') as String,
        contentType: j['content_type'] as String?,
        sizeBytes: j['size_bytes'] as int?,
        status: (j['status'] ?? 'pending') as String,
        error: j['error'] as String?,
        chunkCount: (j['chunk_count'] ?? 0) as int,
      );

  bool get isDone => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isBusy => status == 'pending' || status == 'processing';
}

class IngestionJob {
  final int id;
  final int documentId;
  final String status; // pending, parsing, chunking, embedding, completed, failed
  final String? stage;
  final int progress; // 0-100
  final int totalChunks;
  final int embeddedChunks;
  final String? error;

  IngestionJob({
    required this.id,
    required this.documentId,
    required this.status,
    this.stage,
    this.progress = 0,
    this.totalChunks = 0,
    this.embeddedChunks = 0,
    this.error,
  });

  factory IngestionJob.fromJson(Map<String, dynamic> j) => IngestionJob(
        id: j['id'] as int,
        documentId: j['document_id'] as int,
        status: (j['status'] ?? 'pending') as String,
        stage: j['stage'] as String?,
        progress: (j['progress'] ?? 0) as int,
        totalChunks: (j['total_chunks'] ?? 0) as int,
        embeddedChunks: (j['embedded_chunks'] ?? 0) as int,
        error: j['error'] as String?,
      );

  bool get isTerminal => status == 'completed' || status == 'failed';
}

/// A retrieved source chunk backing a grounded answer (a citation).
class SourceChunk {
  final int index;
  final int chunkId;
  final int documentId;
  final String documentName;
  final int ordinal;
  final String text;
  final double score;

  SourceChunk({
    required this.index,
    required this.chunkId,
    required this.documentId,
    required this.documentName,
    required this.ordinal,
    required this.text,
    required this.score,
  });

  factory SourceChunk.fromJson(Map<String, dynamic> j) => SourceChunk(
        index: (j['index'] ?? 0) as int,
        chunkId: (j['chunk_id'] ?? 0) as int,
        documentId: (j['document_id'] ?? 0) as int,
        documentName: (j['document_name'] ?? 'document') as String,
        ordinal: (j['ordinal'] ?? 0) as int,
        text: (j['text'] ?? '') as String,
        score: ((j['score'] ?? 0) as num).toDouble(),
      );
}
