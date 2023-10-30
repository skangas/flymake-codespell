;;; flymake-codespell.el --- Flymake backend for codespell  -*- lexical-binding: t -*-

;; Copyright (C) 2022-2023 Free Software Foundation, Inc.

;; Author     : Stefan Kangas <stefankangas@gmail.com>
;; Maintainer : Stefan Kangas <stefankangas@gmail.com>
;; Version    : 0.1
;; URL        : https://www.github.com/skangas/flymake-codespell
;; Keywords   : extensions
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "26.1") (compat "29.1.4.2"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This adds a codespell backend for `flymake-mode' in Emacs.
;;
;; Unlike most other spellcheckers, codespell does not have a dictionary of
;; known words.  Instead it has a list of common typos, and checks only for
;; those.  This means that it’s far less likely to generate false
;; positives, especially when used on source code, or any file with a lot
;; of specific terms like documentation or research.
;; 
;; Install this package using
;;
;;     M-x package-install RET codespell RET
;;
;; Then add this to your init file, or evaluate it using `M-:':
;;
;;     (add-hook 'prog-mode-hook 'flymake-codespell-setup-backend)
;;
;; If you prefer `use-package', you could use this instead:
;;
;;     (use-package flymake-codespell
;;       :hook (prog-mode . flymake-codespell-setup-backend))
;;
;; This requires codespell to be installed and available in your
;; `exec-path'.
;;
;; See the file README.org in this repository for more details.
;;
;; Bug reports, comments, and suggestions are welcome!  Send them to
;; Stefan Kangas <stefankangas@gmail.com> or report them on GitHub.

;;; Code:

(require 'flymake)

(defgroup flymake-codespell nil
  "Flymake backend for codespell."
  :group 'tools)

(defcustom flymake-codespell-program "codespell"
  "Name of the codespell executable."
  :type 'string)

(defcustom flymake-codespell-program-arguments ""
  "Arguments passed to the codespell executable.
The \"--disable-colors\" flag is passed unconditionally.

See the Man page `codespell' or the output of running the command
\"codespell --help\" for more details."
  :type 'string)

(defvar flymake-codespell--process nil
  "Currently running codespell process.")

(defun flymake-codespell--make-diagnostic (word locus beg end type text)
  "Like `flymake-make-diagnostic' but adjust to highlight column.
WORD is the word that should be highlighted.
LOCUS, BEG, END, TYPE and TEXT are passed as is to
`flymake-make-diagnostic'."
  (with-current-buffer locus
    (save-excursion
      (goto-char beg)
      (when (search-forward word (pos-eol) t)
        (setq beg (match-beginning 0)
              end (match-end 0)))))
  (flymake-make-diagnostic locus beg end type text))

(defun flymake-codespell-backend (report-fn &rest _args)
  ;; (message "CALLED BACKEND")
  (unless (executable-find flymake-codespell-program)
    (error "Could not find a \"codespell\" executable"))
  (when (process-live-p flymake-codespell--process)
    (kill-process flymake-codespell--process))
  (let ((source (current-buffer)))
    (save-restriction
      (widen)
      (setq
       flymake-codespell--process
       (make-process
        :name "flymake-codespell" :noquery t :connection-type 'pipe
        :buffer (generate-new-buffer " *flymake-codespell*")
        :command `(,flymake-codespell-program
                   "--disable-colors"
                   ,@(when (and (stringp flymake-codespell-program-arguments)
                                (> (length flymake-codespell-program-arguments) 0))
                       (list flymake-codespell-program-arguments))
                   "-")
        :sentinel
        (lambda (proc _event)
          (when (memq (process-status proc) '(exit signal))
            (unwind-protect
                (when (with-current-buffer source (eq proc flymake-codespell--process))
                  (with-current-buffer (process-buffer proc)
                    ;; (message (buffer-string))
                    (goto-char (point-min))
                    (cl-loop
                     while (re-search-forward
                            (rx bol
                                (group (+ digit)) ": ;; " (+ nonl) "\n"
                                (+ space) (group (+ any)) " ==> " (group (+ any)))
                            nil t)
                     for typo = (match-string 2)
                     for correction = (match-string 3)
                     for msg = (format "codespell: %s ==> %s" typo correction)
                     for (beg . end) = (flymake-diag-region
                                        source
                                        (string-to-number (match-string 1)))
                     when (and beg end)
                     collect (flymake-codespell--make-diagnostic
                              typo
                              source
                              beg
                              end
                              :error
                              msg)
                     into diags
                     finally (funcall report-fn diags)))
                  (flymake-log :warning "Canceling obsolete check %s"
                               proc))
              (kill-buffer (process-buffer proc)))))))))
  (process-send-region flymake-codespell--process (point-min) (point-max))
  (process-send-eof flymake-codespell--process))

(defun flymake-codespell-setup-backend ()
  (add-hook 'flymake-diagnostic-functions 'flymake-codespell-backend nil t))

;; LocalWords: codespell backend

(provide 'flymake-codespell)

;;; flymake-codespell.el ends here
