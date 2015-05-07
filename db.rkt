#lang racket

(require db)

(provide db-conn db-reset)

(define db-conn
  (virtual-connection
   (connection-pool
    (lambda () (sqlite3-connect	#:database "emacsconfigs.sqlite3")))))

(define (db-reset)
  (for ([q '("DROP TABLE IF EXISTS repo"
             "CREATE TABLE repo (
id         INTEGER PRIMARY KEY,
github_id   INTEGER NOT NULL,
name        TEXT NOT NULL,
stars       INTEGER NOT NULL,
owner_login TEXT NOT NULL,
html_url    TEXT NOT NULL
)"
             "DROP TABLE IF EXISTS file"
             "CREATE TABLE file (
id      INTEGER PRIMARY KEY,
rid      INTEGER NOT NULL,
name     TEXT NOT NULL,
content TEXT NOT NULL
)"
             )])
    (query-exec db-conn q)))
