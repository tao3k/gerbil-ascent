;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider))
(export gerbil-ascent-movie-cast-program)

;;; One admitted template; movie bindings and bans remain replaceable sources.
;;; Film and Actor are distinct finite domains. The actor variable is shared
;;; across differently anchored film evidence, before output projection.
;; : (-> FilmRows ActorRows CastRows FilmRows FilmRows ActorRows Symbol Symbol Program)
(def (gerbil-ascent-movie-cast-program films actors cast left right blocked combine exclusion)
  (unless (and (memq combine '(any all)) (memq exclusion '(none left both))
               (list? films) (list? actors)
               (andmap (lambda (row) (and (list? row) (= (length row) 1) (symbol? (car row)))) (append films actors))
               (not (find (lambda (row) (member row actors)) films)))
    (error "invalid movie/actor query contract"))
  (let* ((film-domain (map car films)) (actor-domain (map car actors))
        (film? (lambda (value) (and (memq value film-domain) #t)))
        (actor? (lambda (value) (and (memq value actor-domain) #t)))
        (f (gerbil-ascent-variable 'film)) (a (gerbil-ascent-variable 'actor)))
    (def (rel name width rows fields)
      (gerbil-ascent-relation name width rows gerbil-ascent-hash-index-provider
        gerbil-ascent-set-storage-provider fields))
    (def (atom name . terms) (gerbil-ascent-atom name terms))
    (def (rule head body) (gerbil-ascent-rule (list head) body))
    (def (support source name masked?)
      (rule (atom name f a)
        (append (list (atom source f) (atom 'cast f a))
          (if masked? (list (gerbil-ascent-negation 'blocked_actor (list a))) []))))
    (gerbil-ascent-program
      (list (rel 'cast 2 cast (list film? actor?))
            (rel 'left_film 1 left (list film?)) (rel 'right_film 1 right (list film?))
            (rel 'blocked_actor 1 blocked (list actor?))
            (rel 'left_evidence 2 [] (list film? actor?))
            (rel 'right_evidence 2 [] (list film? actor?))
            (rel 'actor_answer 1 [] (list actor?))
            (rel 'cast_trace 3 [] (list (lambda (x) (memq x '(left right))) film? actor?)))
      (append
        (list (support 'left_film 'left_evidence (memq exclusion '(left both)))
              (support 'right_film 'right_evidence (eq? exclusion 'both)))
        (if (eq? combine 'any)
          (list (rule (atom 'actor_answer a) (list (atom 'left_evidence f a)))
                (rule (atom 'actor_answer a) (list (atom 'right_evidence f a))))
          (list (rule (atom 'actor_answer a)
            (list (atom 'left_evidence f a)
                  (atom 'right_evidence (gerbil-ascent-variable 'other_film) a)))))
        (list (rule (atom 'cast_trace (gerbil-ascent-literal 'left) f a)
                (list (atom 'actor_answer a) (atom 'left_evidence f a)))
              (rule (atom 'cast_trace (gerbil-ascent-literal 'right) f a)
                (list (atom 'actor_answer a) (atom 'right_evidence f a)))))
      4096 16384 32768)))
