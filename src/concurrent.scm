
(module concurrent *

	  (import scheme (chicken base) (chicken condition) (chicken foreign) aux fds-queue (chicken pretty-print))

    #>
    #include <zmq.h>
    extern C_word C_zmq_ctx_new (C_word);
    extern C_word C_pthread_create (C_word);
    <#

    (define ZMQ-REP (foreign-value "ZMQ_REP" int))

    (define-record concurrent-system rdyQ)

    (define (concurrent-system-empty)
      (letqueue ((q '()))
        (make-concurrent-system q)))

    (define (concurrent-system-rdyQ-enqueue! cos k)
      (concurrent-system-rdyQ-set! cos (fds-queue-cons k (concurrent-system-rdyQ cos))))

    (define (concurrent-system-rdyQ-dequeue! cos)
      (let* ((rdyQ (concurrent-system-rdyQ cos))
             (k (fds-queue-car rdyQ)))
        (concurrent-system-rdyQ-set! cos (fds-queue-cdr rdyQ))
        k))

    (define (concurrent-system-dispatch! cos)
      (let ((rdyQ (concurrent-system-rdyQ cos)))
        (cond
          ((fds-queue-empty? rdyQ) (signal (condition '(exn message "deadlock"))))
          (else ((concurrent-system-rdyQ-dequeue! cos))))))

    (define (concurrent-system-yield! cos)
      (letcc k 
        (concurrent-system-rdyQ-enqueue! cos k)
        (concurrent-system-dispatch! cos)))

    (define (concurrent-system-spawn! cos thunk)
        (let ((t (letcc j
                    (letcc k (j k))
                    #;(with-exception-handler (λ (x) (pretty-print x)) thunk)
                    (thunk)
                    (concurrent-system-dispatch! cos))))
            (concurrent-system-rdyQ-enqueue! cos t)))

    (define-syntax concurrent-system-spawn
      (syntax-rules ()
        ((_ cos body ...) (concurrent-system-spawn! cos (λ () body ...)))))

    (define zmq-ctx-new (foreign-lambda scheme-object "C_zmq_ctx_new" scheme-object))
    (define pthread-create (foreign-safe-lambda scheme-object "C_pthread_create" scheme-object))

    (define-record concurrent-channel sync? sendQ recvQ cos)

    (define (concurrent-channel-sendQ-enqueue! ch v)
      (concurrent-channel-sendQ-set! ch (fds-queue-cons v (concurrent-channel-sendQ ch))))

    (define (concurrent-channel-sendQ-dequeue! ch)
      (let* ((sendQ (concurrent-channel-sendQ ch))
             (v (fds-queue-car sendQ)))
        (concurrent-channel-sendQ-set! ch (fds-queue-cdr sendQ))
        v))

    (define (concurrent-channel-recvQ-enqueue! ch v)
      (concurrent-channel-recvQ-set! ch (fds-queue-cons v (concurrent-channel-recvQ ch))))

    (define (concurrent-channel-recvQ-dequeue! ch)
      (let* ((recvQ (concurrent-channel-recvQ ch))
             (v (fds-queue-car recvQ)))
        (concurrent-channel-recvQ-set! ch (fds-queue-cdr recvQ))
        v))

    (define (concurrent-channel-async cos)
      (letqueue ((s '()) (r '()))
        (make-concurrent-channel #f s r cos)))

    (define (concurrent-channel-sync cos)
      (letqueue ((s '()) (r '()))
        (make-concurrent-channel #t s r cos)))
    
    (define (concurrent-channel-send ch msg)
      (let ((cos (concurrent-channel-cos ch))
            (sendQ (concurrent-channel-sendQ ch))
            (recvQ (concurrent-channel-recvQ ch)))
        (letcc k
          (cond 
            ((concurrent-channel-sync? ch)
              (cond 
                ((fds-queue-empty? recvQ)
                  (concurrent-channel-sendQ-enqueue! ch (cons msg k))
                  (concurrent-system-dispatch! cos))
                (else
                  (concurrent-system-rdyQ-enqueue! cos k)
                  ((concurrent-channel-recvQ-dequeue! ch) msg))))
            (else
              (concurrent-system-rdyQ-enqueue! cos k)
              (cond 
                ((fds-queue-empty? recvQ)
                  (concurrent-channel-sendQ-enqueue! ch msg)
                  (concurrent-system-dispatch! cos))
                (else (letcar&cdr (((id recvK) (concurrent-channel-recvQ-dequeue! ch)))
                        (recvK (cons id msg))))))))))

    (define (concurrent-channel-recv ch)
      (let ((cos (concurrent-channel-cos ch))
            (sendQ (concurrent-channel-sendQ ch))
            (recvQ (concurrent-channel-recvQ ch)))
        (cond 
          ((concurrent-channel-sync? ch)
            (letcc k
              (cond 
                ((fds-queue-empty? sendQ)
                  (concurrent-channel-recvQ-enqueue! ch k)
                  (concurrent-system-dispatch! cos))
                (else (letcar&cdr (((msg senderK) (concurrent-channel-sendQ-dequeue! ch)))              
                        (concurrent-system-rdyQ-enqueue! cos senderK)
                        msg)))))
          (else
            (cond 
              ((fds-queue-empty? sendQ)
                (letcar&cdr (((_ msg) (letcc k
                                        (concurrent-channel-recvQ-enqueue! ch (cons (gensym) k))
                                        (concurrent-system-dispatch! cos))))
                  msg))
              (else (concurrent-channel-sendQ-dequeue! ch)))))))

    (define-syntax letchannel
      (syntax-rules ()
        ((_ cos ((ch sync?) ...) body ...)
         (let ((ch ((if sync? concurrent-channel-sync concurrent-channel-async) cos)) ...)
           body ...))))

    (define (concurrent-channel-filter chin chout p?)
      (let1 (cos (concurrent-channel-cos chin))      
        (concurrent-system-spawn cos
          (let loop () 
            (let1 (msg (concurrent-channel-recv chin))
              (when (p? msg) (concurrent-channel-send chout msg))
              (loop))))))

    #;(define (concurrent-channel-select! cos choices)
      (letrec ((pollCh (λ (pair)
                          (letcar&cdr (((ch thunk) pair))
                            (fds-queue-empty? (concurrent-channel-sendQ ch)))))
               (wait (λ (ids k)
                        (for-each (λ (pair)
                                    (letcar&cdr (((id ch) pair))
                                      (concurrent-channel-recvQ-set! ch 
                                        (fds-queue-cons (cons id k) concurrent-channel-recvQ ch))))
                                  ids)
                        (concurrent-system-dispatch! cos)))
                (remove (λ (id ids)
                          (filter (λ (pair) (not (eq? id (car pair)))) ids))))
        (let ((readies (filter pollCh choices)))
          (if (null? readies)
            (let ((ids (map (λ (pair) (cons (gensym) pair)) choices)))
              (letcar&cdr (((id msg) (letcc k (wait ids k))))
                ((remove id ids) msg)))
            (letcar&cdr ((((ch f) (car readies)))
              (let* ((sendQ (concurrent-channel-sendQ ch))
                     (msg (fds-queue-car sendQ)))
                (concurrent-channel-sendQ-set! ch (fds-queue-cdr sendQ))
                (f msg))))))))
    
    
)
