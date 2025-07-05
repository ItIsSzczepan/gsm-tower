
struct ConcurrencyLimiter {
    let limit: Int
    
    func run(tasks: [() async throws -> Void]) async throws {
        guard !tasks.isEmpty else { return }
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = tasks.makeIterator()
            var active = 0
            
            // pierwsza porcja
            while active < limit, let next = iterator.next() {
                group.addTask { try await next() }
                active += 1
            }
            
            while active > 0 {
                _ = try await group.next()
                active -= 1
                if let next = iterator.next() {
                    group.addTask { try await next() }
                    active += 1
                }
            }
        }
    }
}

