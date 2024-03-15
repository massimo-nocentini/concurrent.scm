
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
    
    (define ((concurrent-channel-send-event ch msg) k)
      (let ((cos (concurrent-channel-cos ch))
            (recvQ (concurrent-channel-recvQ ch)))
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
              (else ((concurrent-channel-recvQ-dequeue! ch) msg)))))))

    (define (concurrent-channel-send ch msg) 
      (callcc (concurrent-channel-send-event ch msg)))

    (define ((concurrent-channel-recv-event ch) k)
      (let ((cos (concurrent-channel-cos ch))
            (sendQ (concurrent-channel-sendQ ch)))
        (cond 
          ((concurrent-channel-sync? ch)
            (cond
              ((fds-queue-empty? sendQ)
                (concurrent-channel-recvQ-enqueue! ch k)
                (concurrent-system-dispatch! cos))
              (else (letcar&cdr (((msg senderK) (concurrent-channel-sendQ-dequeue! ch)))              
                      (concurrent-system-rdyQ-enqueue! cos senderK)
                      msg))))
          (else 
            (cond
              ((fds-queue-empty? sendQ)
                (concurrent-channel-recvQ-enqueue! ch k)
                (concurrent-system-dispatch! cos))
              (else (concurrent-channel-sendQ-dequeue! ch)))))))

    (define (concurrent-channel-recv ch)
      (callcc (concurrent-channel-recv-event ch)))

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

    (define ((concurrent-event-wrap-event evt f) k)
      (k (f (callcc evt))))
    
    (define-syntax λ-wrap-event
      (syntax-rules ()
        ((_ evt args body ...) (concurrent-event-wrap-event evt (λ args body ...)))))

)
