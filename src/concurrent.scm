
(module concurrent *

	(import scheme (chicken continuation) (chicken base))

	(define-syntax let/cc 
          (syntax-rules () 
            ((let/cc hop body ...) (continuation-capture
				    (lambda (cont)
				      (let ((hop (lambda args
						   (apply continuation-return cont args))))
					body ...))))))

	(define concurrent-queue-empty (cons '() '()))

	(define (concurrent-queue-empty? q)
	  (null? (car q)))

	(define (concurrent-queue-car q)
	  (cond
	   ((concurrent-queue-empty? q) (error 'empty))
	   (else (caar q))))
 
    (define (concurrent-queue-check q)
	  (cond
	   ((null? (car q)) (cons (reverse (cdr q)) '()))
	   (else q)))
 
   	(define (concurrent-queue-cdr q)
	  (cond
	   ((concurrent-queue-empty? q) (error 'empty))
	   (else (concurrent-queue-check (cons (cadr q) (cdr q))))))
 
    (define (concurrent-queue-push q x)
        (concurrent-queue-check (cons (car q) (cons x (cdr q)))))
 
)
