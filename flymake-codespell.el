;;; flymake-codespell.el --- Flymake backend for codespell  -*- lexical-binding: t -*-

;; Copyright (C) 2022  Stefan Kangas

;; Author: Stefan Kangas <stefankangas@gmail.com>
;; Keywords: extensions

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

;; To use this, install this package and add this to your init file:
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

;;; Code:

(require 'flymake)

(defgroup flymake-codespell nil
  "Flymake backend for codespell."
  :group 'tools)

(defcustom flymake-codespell-program "codespell"
  "Name of the codespell executable."
  :type 'string)

(defvar flymake-codespell--process nil
  "Currently running proceeed codespell process.")

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
        :command `(,flymake-codespell-program "--disable-colors" "-")
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
                            (rx bol (group (+ digit)) ": ;; " (+ nonl) "\n"
                                (+ space)
                                (group (+ any) " ==> " (+ any)))
                            nil t)
                     for msg = (format "codespell: %s" (match-string 2))
                     for (beg . end) = (flymake-diag-region
                                        source
                                        (string-to-number (match-string 1)))
                     when (and beg end)
                     collect (flymake-make-diagnostic source
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