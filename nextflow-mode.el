;;; nextflow-mode.el --- Major mode for editing Nextflow files -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2020 Edmund Miller
;;
;; Author: Edmund Miller <http://github/emiller88>
;; Maintainer: Edmund Miller <Edmund.A.Miller@gmail.com>
;; Created: February 28, 2020
;; Modified: December 26, 2024
;; Version: 0.0.1
;; Keywords: tools nextflow bioinformatics
;; Homepage: https://github.com/emiller88/nextflow-mode
;; Package-Requires: ((emacs "24.5") (groovy-mode "2.1"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;; This package provides syntax highlighting and indentation support for Nextflow files.
;; Nextflow is a reactive workflow framework and domain-specific language (DSL)
;; for writing data-driven computational pipelines.
;;
;; Features:
;; - Syntax highlighting for Nextflow keywords, directives and blocks
;; - Proper indentation handling
;; - Imenu integration for quick navigation
;; - Inherits from groovy-mode for base language support
;;
;;; Code:



(require 'cl-lib)
(require 'groovy-mode)


;;; Customization

;;;###autoload
(defgroup nextflow nil
  "Support for Nextflow files."
  :group 'tools
  :prefix "nextflow-")

(defcustom nextflow-mode-hook nil
  "Hook run when entering `nextflow-mode'."
  :type 'hook
  :group 'nextflow)

(defcustom nextflow-indent-field-offset 4
  "Offset for field indentation in Nextflow blocks."
  :type 'integer
  :group 'nextflow)

(defcustom nextflow-indent-value-offset 4
  "Offset for field values that appear on the line below the field key."
  :type 'integer
  :group 'nextflow)


;;; Regexp

(eval-and-compile
  (defconst nextflow-rx-constituents
    `((nf-type . ,(rx (and (group symbol-start
                                  (or "val"
                                      "env"
                                      "eval"
                                      "file"
                                      "path"
                                      "stdin"
                                      "tuple"
                                      "each"
                                      "stdout"
                                      "Channel"
                                      "Date"
                                      "Map"
                                      "List"))
                           symbol-end
                           (zero-or-one (and " "
                                             (one-or-more
                                              (or (syntax word) (syntax symbol))) ":"))
                           (zero-or-one (and " "
                                             (group (one-or-more
                                                     (or (syntax word) (syntax symbol)))))))))
      (nf-function . ,(rx (and (group symbol-start
                                      (or "process"
                                          "workflow"
                                          "function"))
                               symbol-end
                               (zero-or-one (and " "
                                                 (group (one-or-more
                                                         (or (syntax word) (syntax symbol)))))))))
      (nf-keyword . ,(rx (group symbol-start
                                (or "from"
                                    "into"
                                    "emit"
                                    "include"
                                    "take"
                                    "main"
                                    "publish"
                                    "return"
                                    "throw"
                                    "try"
                                    "catch"
                                    "finally"
                                    "as"
                                    "in"
                                    "instanceof"
                                    "new"
                                    "view"
                                    "set"
                                    "branch"))
                         symbol-end))
      (nf-operator . ,(rx (group (or "=~" "==~" "!~" 
                                     "|" "||"
                                     ".&" ".flatten" ".collect"
                                     ".mix" ".dump" ".view"
                                     ".set" ".into" ".map" ".filter"))))
      (nf-interpolation . ,(rx (group "${" (one-or-more (not "}")) "}")))
      (nf-directive . ,(rx (group symbol-start
                                  (or "accelerator"
                                      "afterScript"
                                      "beforeScript"
                                      "cache"
                                      "clusterOptions"
                                      "conda"
                                      "container"
                                      "containerOptions"
                                      "cpus"
                                      "debug"
                                      "disk"
                                      "echo"
                                      "errorStrategy"
                                      "executor"
                                      "ext"
                                      "label"
                                      "machineType"
                                      "maxErrors"
                                      "maxForks"
                                      "maxRetries"
                                      "memory"
                                      "module"
                                      "penv"
                                      "pod"
                                      "publishDir"
                                      "queue"
                                      "scratch"
                                      "stageInMode"
                                      "stageOutMode"
                                      "storeDir"
                                      "tag"
                                      "time"))
                           symbol-end))
      (nf-block . ,(rx (group symbol-start
                              (or "input"
                                  "output"
                                  "when"
                                  "script"
                                  "shell"
                                  "exec"
                                  "stub"
                                  "directives"))
                       symbol-end))
      (nf-workflow-body . ,(rx (group symbol-start
                                      (or "take"
                                          "main"
                                          "emit"))
                               symbol-end))
      (nf-special . ,(rx (group symbol-start
                                (or "baseDir"
                                    "launchDir"
                                    "moduleDir"
                                    "nextflow"
                                    "params"
                                    "projectDir"
                                    "workDir"
                                    "workflow"
                                    "it"
                                    "true"
                                    "false"))
                         symbol-end))
      (nf-constant . ,(rx (group symbol-start
                                 (or "null"))
                          symbol-end)))
    "Nextflow-specific sexps for `nextflow-rx'.")

  (defmacro nextflow-rx (&rest regexps)
    "Specialized `rx' for Nextflow mode."
    (let ((rx-constituents (append nextflow-rx-constituents rx-constituents)))
      (cond ((null regexps)
             (error "No regexp"))
            ((cdr regexps)
             (rx-to-string `(and ,@regexps) t))
            (t
             (rx-to-string (car regexps) t))))))

(defconst nextflow-imenu-re
  (nextflow-rx line-start (zero-or-more space)
               (or nf-type nf-function nf-keyword nf-block nf-workflow-body))
  "Regexp matching something that should go in imenu.")


;;; Imenu

(defun nextflow-imenu-create-index ()
  "Create Imenu index for Nextflow processes and workflow blocks.
Returns an alist of name and position pairs for imenu navigation."
  (let ((nf-index (nextflow--imenu-build-rule-index)))
    nf-index))

(defun nextflow--imenu-build-rule-index ()
  "Build the raw index of rule names and positions."
  (goto-char (point-min))
  (let (index)
    (while (re-search-forward nextflow-imenu-re nil t)
      (push (cons (match-string-no-properties 2)
                  (save-excursion (beginning-of-line)
                                  (point-marker)))
            index))
    (nreverse index)))


;;; Mode

(defvar nextflow--font-lock-keywords
  `((,(nextflow-rx line-start (zero-or-more space) nf-function)
     (1 font-lock-keyword-face nil 'lax)
     (2 font-lock-function-name-face nil 'lax))
    (,(nextflow-rx line-start (one-or-more space) nf-type)
     (1 font-lock-type-face nil 'lax)
     (2 font-lock-variable-name-face nil 'lax))
    (,(nextflow-rx line-start (one-or-more space) nf-block
                   (zero-or-more space) ":")
     1 font-lock-keyword-face)
    (,(nextflow-rx line-start (one-or-more space) nf-workflow-body
                   (zero-or-more space) ":")
     1 font-lock-keyword-face)
    (,(nextflow-rx line-start (one-or-more space) nf-directive)
     1 font-lock-preprocessor-face)
    (,(nextflow-rx nf-special)
     1 font-lock-builtin-face)
    (,(nextflow-rx nf-keyword)
     1 font-lock-keyword-face)
    (,(nextflow-rx nf-operator)
     1 font-lock-builtin-face)
    (,(nextflow-rx nf-interpolation)
     1 font-lock-variable-name-face)))

(if (bound-and-true-p groovy-font-lock-keywords-level-1)
    (with-no-warnings
      ;; In Emacs 27 `groovy-font-lock-keywords' was split up into
      ;; different decoration levels.
      (defvar nextflow-font-lock-keywords-level-1
        (append nextflow--font-lock-keywords
                groovy-font-lock-keywords-level-1))
      (defvar nextflow-font-lock-keywords-level-2
        (append nextflow--font-lock-keywords
                groovy-font-lock-keywords-level-2))
      (defvar nextflow-font-lock-keywords-maximum-decoration
        (append nextflow--font-lock-keywords
                groovy-font-lock-keywords-maximum-decoration))
      (defvar nextflow-font-lock-keywords
        ;; Mirrors `groovy-font-lock-keywords'.
        '(nextflow-font-lock-keywords-level-1
          nextflow-font-lock-keywords-level-1
          nextflow-font-lock-keywords-level-2
          nextflow-font-lock-keywords-maximum-decoration)))
  (defvar nextflow-font-lock-keywords
    (append nextflow--font-lock-keywords groovy-font-lock-keywords)))

(defun nextflow--indent-syntax-ppss (orig-fun &rest args)
  (let ((syntax-bol (apply orig-fun args)))
    (setf (nth 3 syntax-bol) nil)
    syntax-bol))

(defun nextflow--ends-with-infix-p (orig-fun str)
  (or (funcall orig-fun str)
      (groovy--ends-with-token-p '("\\") str)))

(defun nextflow-indent-line ()
  "Indent the current line according to the number of parentheses."
  (interactive)
  (unwind-protect
      (progn
        (advice-add 'syntax-ppss :around 'nextflow--indent-syntax-ppss)
        (advice-add 'groovy--ends-with-infix-p :around 'nextflow--ends-with-infix-p)
        (groovy-indent-line))
    (progn
      (advice-remove 'syntax-ppss 'nextflow--indent-syntax-ppss)
      (advice-remove 'groovy--ends-with-infix-p 'nextflow--ends-with-infix-p))))

;;;###autoload
(define-derived-mode nextflow-mode groovy-mode "Nextflow"
  "Mode for editing Nextflow files."
  (set (make-local-variable 'imenu-create-index-function)
       #'nextflow-imenu-create-index)
  (set (make-local-variable 'font-lock-defaults)
       (cons nextflow-font-lock-keywords (cdr font-lock-defaults)))
  (set (make-local-variable 'indent-line-function) #'nextflow-indent-line)
  (let ((shrt-buf  (file-name-nondirectory buffer-file-name)))
    (setq-local compile-command
		(concat "nextflow "
			(shell-quote-argument shrt-buf))
		compilation-buffer-name-function
		(lambda (_mode)
		  (concat "* Nextflowing " shrt-buf "*")))
    )
  )

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.\\(?:nf\\)?patterns\\'" . nextflow-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.nf\\'" . nextflow-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.nf.test\\'" . nextflow-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.nextflow\\'" . nextflow-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\nextflow.config\\'" . nextflow-mode))

(provide 'nextflow-mode)
;;; nextflow-mode.el ends here
