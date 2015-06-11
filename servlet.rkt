#lang web-server

(require octokit
         racket/system
;;         web-server/
         net/base64
         "db.rkt"
         db)

(provide interface-version stuffer start)
(define interface-version 'stateless)

(define gh (new octokit%))

(define (start req)
  (site-router req))

(define-values (site-router site-url)
  (dispatch-rules
   [("") serve-home]
;;   [("/favicon.ico") serve-favicon]
   [((string-arg)) serve-profile]))

;; (define (serve-favicon req)
;;   (files:make
;;    #:url->path (fsmap:make-url->path "/favicon.ico")))

;; (static-files-path "/favicon.ico"))

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

(define (sync-to-db conn repo file)
  (query-exec conn "INSERT INTO repo(github_id, name, stars, owner_login, html_url)
VALUES (?, ?, ?, ?, ?)"
              (hash-ref repo 'id) (hash-ref repo 'name) (hash-ref repo 'stargazers_count)
              (hash-ref (hash-ref repo 'owner) 'login) (hash-ref repo 'html_url))
  ;; TODO: What if the above query fails?
  ;; Get the rid.
  (define rid (vector-ref
               (query-row conn
                          "SELECT * FROM repo WHERE github_id=?"
                          (hash-ref repo 'id))
               0))

  (query-exec conn "INSERT INTO file(rid, name, content) VALUES (?, ?, ?)"
              rid (hash-ref file 'name) (hash-ref file 'content)))

(struct repo (id
              github-id
              name
              stars
              owner-login
              html-url))

(struct file (id
              rid
              name
              content))

(define (get-repo-from-db conn owner-login)
  (define row (rows-result-rows (query conn
                                       "SELECT * FROM repo WHERE owner_login=?"
                                       owner-login)))
  (if (equal? (length row) 0)
      #f
      (let ([r (car row)])
        (repo (vector-ref r 0)
              (vector-ref r 1)
              (vector-ref r 2)
              (vector-ref r 3)
              (vector-ref r 4)
              (vector-ref r 5)))))

(define (get-files-from-db conn rid)
  (define rows (rows-result-rows (query conn
                                       "SELECT * FROM file WHERE rid=?"
                                       rid)))
  (map (lambda (f)
         (file (vector-ref f 0)
               (vector-ref f 1)
               (vector-ref f 2)
               ;; Unhash content.
               (bytes->string/utf-8
                (base64-decode
                 (string->bytes/utf-8 (vector-ref f 3))))))
       rows))

;; sync to database & return repo and file.
;; return (cons repo files) or nil.
;; TODO: Handle contract violations (message . "Not Found").
(define (process-github-data url)
  ;; If any of the repos are in our db, we assume it's "correct" and
  ;; that we've processed it.
  (define stored-repo (get-repo-from-db db-conn url))
  (if (not (equal? stored-repo #f))
      (cons stored-repo (get-files-from-db db-conn (repo-id stored-repo)))
      ;; Get the info & save it to the db.
      (let ([repos (send gh user-repos url)])
        (if (equal? (hash-ref repos 'message "") "Not Found")
            #f
            (let ([emacs-repos
                   (filter (lambda (r)
                             (define n (hash-ref r 'name))
                             (unless (ormap (lambda (x) (equal? n x))
                                            '(".emacs.d" "dotemacsd" "dot-emacs" "dotfiles"))
                               #f))
                           repos)])
              ;; (cons gh-repo gh-content)
              (match-define (cons gh-repo gh-content)
                (ormap (lambda (r)
                         (let ([i (select-contents
                                   (hash-ref (hash-ref r 'owner) 'login)
                                   (hash-ref r 'name))])
                           (if (not (equal? i ""))
                               (cons r i)
                               #f)))
                       emacs-repos))
              (sync-to-db db-conn gh-repo gh-content)
              (define stored-repo (get-repo-from-db db-conn url))
              (cons stored-repo (get-files-from-db db-conn (repo-id stored-repo))))))))


(define (select-contents login repo)
  (define (get-nonempty-content path)
    (define contents (send gh get-contents login repo path))
    (if (not (equal? (hash-ref contents 'type #f) "file"))
        #f
        contents))
  (ormap
   get-nonempty-content
   '("init.el" ".emacs" ".emacs.d/init.el" "spacemacs/.spacemacs")))

;; url must be a single string (like "samertm").
(define (serve-profile req url)
  (with-handlers
    ([exn:fail?
      (lambda (v)
        (displayln (format "On url ~a:\n~a" url v))
        (response/xexpr
         `(html
           (body
            (p "Could not get Emacs config for " ,url)))))])

    (let ([data (process-github-data url)])
      (if (not data)
          (response/xexpr
           `(html (body (p ,(format "No Emacs config found for ~a." url)))))
          (match-let ([(cons repo files) data])
            (response/xexpr
             `(html (body (p "Emacs config for " (a ([href ,(string-append "https://github.com/" url)]) , url))
                          (p (a ([href ,(repo-html-url repo)]) "View on GitHub."))
                          ,@(map (lambda (f)
                                   `(pre ,(file-content f)))
                                 files)))))))))

;; Vestigial limb from when I was cloning repos.
;; (define (get-emacs-config clone-url)
;;   (displayln clone-url)
;;   (let* ([url (string->url clone-url)]
;;          [dir (apply build-path
;;                      (find-system-path 'temp-dir)
;;                      (url-host url)
;;                      (map path/param-path (url-path url)))])
;;     (when (not (directory-exists? dir))
;;       ;; init git dir
;;       ;; what does `parameterize' do?
;;       (make-directory* dir)
;;       (parameterize ([current-directory dir])
;;         (system "git init")
;;         ;; security?
;;         (system (string-append "git remote add origin " clone-url))))
;;     (parameterize ([current-directory dir])
;;       (system "git pull origin master") ;; use real remote branch?
;;       (define init-file (ormap (lambda (f)
;;                                  (define full (build-path dir f))
;;                                  (if (file-exists? full)
;;                                      full
;;                                      #f))
;;                                '("init.el" ".emacs"
;;                                  ".emacs.d/init.el" "spacemacs/.spacemacs")))
;;       (port->string (open-input-file init-file)))))
