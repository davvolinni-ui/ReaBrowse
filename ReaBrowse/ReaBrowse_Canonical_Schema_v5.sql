-- ReaBrowse canonical library schema v5
-- Platform-neutral and transport-neutral: usable through the official
-- sqlite3 CLI today and a persistent helper later without library migration.

PRAGMA foreign_keys=ON;
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA temp_store=MEMORY;
PRAGMA busy_timeout=5000;

CREATE TABLE IF NOT EXISTS app_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS roots (
    id INTEGER PRIMARY KEY,
    identity TEXT NOT NULL UNIQUE,
    display_path TEXT NOT NULL,
    path_norm TEXT NOT NULL,
    platform TEXT,
    case_sensitive INTEGER NOT NULL DEFAULT 0,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    last_checked_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_roots_path_norm ON roots(path_norm);

CREATE TABLE IF NOT EXISTS folders (
    id INTEGER PRIMARY KEY,
    root_id INTEGER NOT NULL REFERENCES roots(id) ON DELETE CASCADE,
    parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    relative_path_norm TEXT NOT NULL,
    missing INTEGER NOT NULL DEFAULT 0,
    UNIQUE(root_id, relative_path_norm)
);
CREATE INDEX IF NOT EXISTS idx_folders_parent
    ON folders(root_id, parent_id, name COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_folders_parent_browse
    ON folders(parent_id, missing, name COLLATE NOCASE, id);

-- Materialized ancestry replaces recursive folder walks in every interactive
-- scope query. It is rebuilt for explicitly scanned roots during the scan
-- transaction; browsing only performs indexed ancestor/descendant lookups.
CREATE TABLE IF NOT EXISTS folder_closure (
    root_id INTEGER NOT NULL REFERENCES roots(id) ON DELETE CASCADE,
    ancestor_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    descendant_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    depth INTEGER NOT NULL CHECK(depth >= 0),
    PRIMARY KEY(ancestor_id, descendant_id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_folder_closure_descendant
    ON folder_closure(descendant_id, ancestor_id);
CREATE INDEX IF NOT EXISTS idx_folder_closure_root
    ON folder_closure(root_id, ancestor_id, depth, descendant_id);

CREATE TABLE IF NOT EXISTS folder_subtree_stats (
    folder_id INTEGER PRIMARY KEY REFERENCES folders(id) ON DELETE CASCADE,
    file_count INTEGER NOT NULL CHECK(file_count >= 0)
) WITHOUT ROWID;

-- One physical file is canonical even when visible through overlapping roots.
CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY,
    canonical_path TEXT NOT NULL,
    canonical_path_norm TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    extension TEXT,
    media_type TEXT NOT NULL CHECK(media_type IN ('audio','midi')),
    file_size INTEGER,
    modified_at INTEGER,
    duration_seconds REAL,
    classification TEXT CHECK(
        classification IS NULL OR
        classification IN ('loop','one-shot','midi','other')),
    automatic_classification TEXT NOT NULL DEFAULT 'other' CHECK(
        automatic_classification IN ('loop','one-shot','midi','other')),
    classification_source TEXT NOT NULL DEFAULT 'automatic',
    classification_confidence REAL NOT NULL DEFAULT 0.0,
    bpm REAL,
    musical_length_beats REAL,
    key_pc INTEGER,
    key_mode TEXT,
    vendor TEXT,
    random_key INTEGER,
    metadata_version INTEGER NOT NULL DEFAULT 1,
    missing INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_files_name
    ON files(name COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_files_type_class
    ON files(media_type, classification, missing);
CREATE INDEX IF NOT EXISTS idx_files_key
    ON files(key_pc, key_mode, missing);
CREATE INDEX IF NOT EXISTS idx_files_random_key
    ON files(random_key, missing);

-- Sparse manual classification decisions. Automatic classification remains on
-- files; this table only stores explicit file/folder/root overrides.
CREATE TABLE IF NOT EXISTS classification_overrides (
    scope_type TEXT NOT NULL CHECK(scope_type IN ('file','folder','root')),
    path_norm TEXT NOT NULL,
    classification TEXT NOT NULL CHECK(
        classification IN ('loop','one-shot','uncategorized')),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY(scope_type, path_norm)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_classification_overrides_path
    ON classification_overrides(path_norm, scope_type);
CREATE INDEX IF NOT EXISTS idx_classification_overrides_class
    ON classification_overrides(classification, scope_type);

-- Sparse per-file musical-key decisions. files.key_pc remains the indexed
-- effective value used by browsing; detected_key_pc preserves the automatic
-- result so clearing an override is immediate and does not require a rescan.
-- A NULL key_pc is an explicit "unkeyed" decision rather than no override.
CREATE TABLE IF NOT EXISTS key_overrides (
    path_norm TEXT PRIMARY KEY,
    key_pc INTEGER CHECK(key_pc IS NULL OR key_pc BETWEEN 0 AND 11),
    detected_key_pc INTEGER CHECK(
        detected_key_pc IS NULL OR detected_key_pc BETWEEN 0 AND 11),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
) WITHOUT ROWID;

-- Cross-platform, incrementally maintained filename/path/vendor search.
-- Existing databases create and populate this once on their first search.
CREATE VIRTUAL TABLE IF NOT EXISTS file_search USING fts5(
    name,
    canonical_path,
    vendor,
    content='files',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);
CREATE TRIGGER IF NOT EXISTS files_search_ai AFTER INSERT ON files BEGIN
    INSERT INTO file_search(rowid,name,canonical_path,vendor)
    VALUES(new.id,new.name,new.canonical_path,new.vendor);
END;
CREATE TRIGGER IF NOT EXISTS files_search_ad AFTER DELETE ON files BEGIN
    INSERT INTO file_search(file_search,rowid,name,canonical_path,vendor)
    VALUES('delete',old.id,old.name,old.canonical_path,old.vendor);
END;
CREATE TRIGGER IF NOT EXISTS files_search_au
AFTER UPDATE OF name,canonical_path,vendor ON files BEGIN
    INSERT INTO file_search(file_search,rowid,name,canonical_path,vendor)
    VALUES('delete',old.id,old.name,old.canonical_path,old.vendor);
    INSERT INTO file_search(rowid,name,canonical_path,vendor)
    VALUES(new.id,new.name,new.canonical_path,new.vendor);
END;

-- A canonical file may appear in more than one configured root.
CREATE TABLE IF NOT EXISTS folder_files (
    root_id INTEGER NOT NULL REFERENCES roots(id) ON DELETE CASCADE,
    folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    relative_path TEXT NOT NULL,
    relative_path_norm TEXT NOT NULL,
    name_sort TEXT NOT NULL,
    missing INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(root_id, relative_path_norm),
    UNIQUE(root_id, folder_id, file_id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_folder_files_folder
    ON folder_files(root_id, folder_id, missing, file_id);
CREATE INDEX IF NOT EXISTS idx_folder_files_file
    ON folder_files(file_id, root_id, missing);
CREATE INDEX IF NOT EXISTS idx_folder_files_root_active
    ON folder_files(root_id, missing, file_id);
CREATE INDEX IF NOT EXISTS idx_folder_files_folder_active
    ON folder_files(folder_id, missing, file_id);
CREATE INDEX IF NOT EXISTS idx_folder_files_folder_name
    ON folder_files(folder_id, missing, name_sort, file_id);

CREATE TABLE IF NOT EXISTS tags (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    name_norm TEXT NOT NULL UNIQUE,
    display_group TEXT
);

CREATE TABLE IF NOT EXISTS file_tags (
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    source TEXT NOT NULL CHECK(
        source IN ('filename','folder','embedded','user','analysis')),
    confidence REAL NOT NULL DEFAULT 1.0,
    PRIMARY KEY(file_id, tag_id, source)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_file_tags_tag
    ON file_tags(tag_id, file_id);
CREATE INDEX IF NOT EXISTS idx_file_tags_file
    ON file_tags(file_id, tag_id);

-- Direct-folder facet counts. These are rebuilt during explicit library
-- updates so opening a root never aggregates every file.
-- Subtree catalogs sum the compact rows for descendant folders.
CREATE TABLE IF NOT EXISTS folder_tag_counts (
    folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    file_count INTEGER NOT NULL CHECK(file_count >= 0),
    PRIMARY KEY(folder_id, tag_id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_folder_tag_counts_tag
    ON folder_tag_counts(tag_id, folder_id);

-- Subtree and global catalogs are scan-time read models. The tag bar no
-- longer recursively walks folders or groups millions of live associations.
CREATE TABLE IF NOT EXISTS folder_subtree_tag_counts (
    folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    file_count INTEGER NOT NULL CHECK(file_count >= 0),
    PRIMARY KEY(folder_id, tag_id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_folder_subtree_tag_counts_tag
    ON folder_subtree_tag_counts(tag_id, folder_id);
CREATE INDEX IF NOT EXISTS idx_folder_subtree_tag_counts_popular
    ON folder_subtree_tag_counts(folder_id, file_count DESC, tag_id);

CREATE TABLE IF NOT EXISTS library_tag_counts (
    tag_id INTEGER PRIMARY KEY REFERENCES tags(id) ON DELETE CASCADE,
    file_count INTEGER NOT NULL CHECK(file_count >= 0)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_library_tag_counts_popular
    ON library_tag_counts(file_count DESC, tag_id);

-- Sparse user decisions that suppress automatically detected tags.
CREATE TABLE IF NOT EXISTS file_tag_exclusions (
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    tag_norm TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY(file_id, tag_norm)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS user_file_data (
    file_id INTEGER PRIMARY KEY REFERENCES files(id) ON DELETE CASCADE,
    favorite INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    play_count INTEGER NOT NULL DEFAULT 0,
    last_used_at INTEGER,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_user_file_recent
    ON user_file_data(last_used_at DESC, file_id);
CREATE INDEX IF NOT EXISTS idx_user_file_used
    ON user_file_data(play_count DESC, last_used_at DESC, file_id);
CREATE INDEX IF NOT EXISTS idx_user_file_favorite
    ON user_file_data(favorite, updated_at DESC, file_id);

CREATE TABLE IF NOT EXISTS collections (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER REFERENCES collections(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS collection_items (
    collection_id INTEGER NOT NULL
        REFERENCES collections(id) ON DELETE CASCADE,
    file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
    root_id INTEGER REFERENCES roots(id) ON DELETE CASCADE,
    folder_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
    added_at INTEGER NOT NULL,
    CHECK(
        (file_id IS NOT NULL AND folder_id IS NULL) OR
        (file_id IS NULL AND folder_id IS NOT NULL AND root_id IS NOT NULL)),
    UNIQUE(collection_id, file_id),
    UNIQUE(collection_id, root_id, folder_id)
);
CREATE INDEX IF NOT EXISTS idx_collection_items_folder
    ON collection_items(folder_id, collection_id);
CREATE INDEX IF NOT EXISTS idx_collection_items_collection_added
    ON collection_items(collection_id, added_at, file_id, folder_id);

-- Stable external identifiers used by smart favorite collections. Keeping
-- these separate from collection_items lets the UI refer to a collection
-- without depending on a display name or numeric ID.
CREATE TABLE IF NOT EXISTS collection_external_keys (
    collection_id INTEGER NOT NULL
        REFERENCES collections(id) ON DELETE CASCADE,
    external_key TEXT NOT NULL UNIQUE,
    PRIMARY KEY(collection_id, external_key)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS idx_collection_external_keys_collection
    ON collection_external_keys(collection_id);

PRAGMA user_version=5;
