#lang racket

(require "servlet.rkt"
         web-server/servlet-env)

(define (main)
  (let ([port 8080])
    (displayln (format "Running server on 0.0.0.0:~s" port))
    (serve/servlet start
                   #:port port
                   #:servlet-regexp #rx""
                   #:command-line? #t)))
(main)
