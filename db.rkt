#lang racket

(require db)

(provide db-conn db-reset db-init)

(define db-name "emacsconfigs.sqlite3")

(define db-conn
  (virtual-connection
   (connection-pool
    (lambda () (sqlite3-connect	#:database db-name)))))

(define (db-reset)
  (when (not (file-exists? db-name))
    ;; Create db.
    (system (string-append "sqlite3 -cmd '.save " db-name "'")))
  (for ([q '("DROP TABLE IF EXISTS repo"
             "DROP TABLE IF EXISTS file")])
    (query-exec db-conn q))
  (db-init))

(define (db-init)
  (when (not (file-exists? db-name))
    ;; Create db.
    (system (string-append "sqlite3 -cmd '.save " db-name "'")))
  (for ([q '("CREATE TABLE IF NOT EXISTS repo (
id         INTEGER PRIMARY KEY,
github_id   INTEGER NOT NULL,
name        TEXT NOT NULL,
stars       INTEGER NOT NULL,
owner_login TEXT NOT NULL,
html_url    TEXT NOT NULL
)"
             "CREATE TABLE IF NOT EXISTS file (
id      INTEGER PRIMARY KEY,
rid      INTEGER NOT NULL,
name     TEXT NOT NULL,
content TEXT NOT NULL
)"
             )])
    (query-exec db-conn q)))
