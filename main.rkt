#lang racket

(require "servlet.rkt"
         "db.rkt"
         web-server/servlet-env
         racket/cmdline)

(define (serve)
  (db-init)
  (let ([port 8888])
    (displayln (format "Running server on 0.0.0.0:~s" port))
    (serve/servlet start
                   #:port port
                   #:servlet-regexp #rx""
                   #:command-line? #t)))

(command-line #:program "emacsconfigs"
              #:usage-help
              "Available commands:"
              "  serve: start server"
              "  db-reset: reset database"
              #:args (cmd)
              (case cmd
                [("serve") (serve)]
                [("db-reset") (db-reset)]))

