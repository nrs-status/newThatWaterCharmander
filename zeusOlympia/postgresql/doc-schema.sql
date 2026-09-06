CREATE TABLE IF NOT EXISTS nodes (
id INTEGER PRIMARY KEY,
title TEXT,
body TEXT,
tags TEXT,             -- comma-sep
fuzzyAux TEXT,
creationDate TEXT      -- ISO 8601
);
