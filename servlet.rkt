#lang web-server

(require octokit
         racket/system)

(provide interface-version stuffer start)
(define interface-version 'stateless)

(define (start req)
  (site-router req))

(define-values (site-router site-url)
  (dispatch-rules
   [("") serve-home]
   [((string-arg)) serve-profile]))

(define (serve-home req)
  (response/xexpr
   `(html
     (body
      (p "Automagically fetch .emacs files for GitHub users.")
      (p "Try it by appending \"/{your username}\" to the url.")
      (p "Check out the following configs:")
      (p (a ([href "/samertm"]) "Samer's config"))
      (p (a ([href "/markmccaskey"]) "Mark's config"))
      (p (a ([href "https://github.com/samertm/emacsconfigs.rkt"]) "Check out the code on GitHub."))))))

;; url must be a single string (like "samertm").
(define (serve-profile req url)
  (with-handlers ([exn:fail? (lambda (v)
                               (displayln v)
                               (response/xexpr
                                `(html
                                  (body
                                   (p "Could not get Emacs config for: " ,url)))))])
    (define repos (send c user-repos url))
    (define emacs-repos (filter (lambda (r)
                                  (define n (hash-ref r 'name))
                                  (unless (ormap (lambda (x) (equal? n x))
                                                 '(".emacs.d" "dotemacsd" "dot-emacs" "dotfiles"))
                                    #f))
                                repos))
    (define emacs-init (ormap (lambda (r)
                                (let ([i (get-emacs-config-string
                                          (hash-ref r 'clone_url))])
                                  (if (not (equal? i ""))
                                      i
                                      #f)))
                              emacs-repos))
    (response/xexpr
     `(html (body (p "Emacs config for: " ,url)
                  (pre ,emacs-init))))))

(define c (new octokit%))

(define (get-emacs-config-string cloneURL)
  (displayln cloneURL)
  (let* ([url (string->url cloneURL)]
         [dir (apply build-path
                     (find-system-path 'temp-dir)
                     (url-host url)
                     (map path/param-path (url-path url)))])
    (when (not (directory-exists? dir))
      ;; init git dir
      ;; what does `parameterize' do?
      (make-directory* dir)
      (parameterize ([current-directory dir])
        (system "git init")
        ;; security?
        (system (string-append "git remote add origin " cloneURL))))
    (parameterize ([current-directory dir])
      (system "git pull origin master") ;; use real remote branch?
      (define init-file (ormap (lambda (f)
                                 (define full (build-path dir f))
                                 (if (file-exists? full)
                                     full
                                     #f))
                               '("init.el" ".emacs"
                                 ".emacs.d/init.el" "spacemacs/.spacemacs")))
      (port->string (open-input-file init-file)))))

