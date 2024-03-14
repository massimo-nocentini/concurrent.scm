
(import scheme (chicken base) aux unittest concurrent (chicken pretty-print))

(define (ℕ-channel cos ch j)
  (concurrent-system-spawn cos
    (let C ((i j))
      (concurrent-channel-send ch i)
      (C (add1 i)))))

(define (primes-channel cos primes)
  (concurrent-system-spawn cos
    (letchannel cos ((ℕ (concurrent-channel-sync? primes)))
      (ℕ-channel cos ℕ 2)
      (let head ((nats ℕ))
        (let ((p (concurrent-channel-recv nats)))
          (concurrent-channel-send primes p)
          (letchannel cos ((filtered (concurrent-channel-sync? primes)))
            (concurrent-channel-filter nats filtered (λ (n) (> (modulo n p) 0)))
            (head filtered)))))))

(define-suite suite

  ((test-empty _)
    (let ((cos (concurrent-system-empty)))
      (concurrent-system-spawn cos
        (print "Hello, World!")
        #;(concurrent-system-yield! cos))
      (concurrent-system-yield! cos)))

  ((test-nat-channel _)
      (let ((cos (concurrent-system-empty)))
        (letchannel cos ((ch #f))
          (ℕ-channel cos ch 0)
          (⊦= 0 (concurrent-channel-recv ch))
          (⊦= 1 (concurrent-channel-recv ch))
          (⊦= 2 (concurrent-channel-recv ch))
          (⊦= 3 (concurrent-channel-recv ch)))))

  ((test-primes-channel _)
      (let* ((cos (concurrent-system-empty))
             (limit 10))
        (letchannel cos ((ch #f))
          (primes-channel cos ch)
          (letrec ((primes (λ (n lst)
                            (if (>= n limit)
                                (reverse lst)
                                (let ((p (concurrent-channel-recv ch)))
                                  #;(print n " " p)
                                  (primes (add1 n) (cons p lst)))))))
            (⊦= '(2 3 5 7 11 13 17 19 23 29) (primes 0 '()))))))

)


(unittest/✓ suite)