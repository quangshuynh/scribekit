//
//  BoundedAudioQueueTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

@Suite("BoundedAudioQueue")
struct BoundedAudioQueueTests {

    @Test("Elements come out in the order they went in")
    func preservesOrder() async {
        let queue = BoundedAudioQueue<Int>(capacity: 4)
        for value in 1...3 { queue.append(value) }
        queue.finish()

        var received: [Int] = []
        for await value in queue { received.append(value) }

        #expect(received == [1, 2, 3])
    }

    @Test("A full queue evicts the oldest element and hands it back")
    func evictsOldestWhenFull() async {
        let queue = BoundedAudioQueue<Int>(capacity: 2)

        #expect(queue.append(1) == nil)
        #expect(queue.append(2) == nil)
        #expect(queue.append(3) == 1)
        #expect(queue.append(4) == 2)

        queue.finish()
        var received: [Int] = []
        for await value in queue { received.append(value) }
        #expect(received == [3, 4])
    }

    @Test("The backlog never exceeds the capacity, however much is appended")
    func staysBounded() {
        let queue = BoundedAudioQueue<Int>(capacity: 8)

        for value in 0..<10_000 { queue.append(value) }

        #expect(queue.count == 8)
    }

    @Test("A consumer waiting on an empty queue is handed the next element")
    func waitsForTheNextElement() async {
        let queue = BoundedAudioQueue<Int>(capacity: 4)
        let consumer = Task { () -> [Int] in
            var received: [Int] = []
            for await value in queue { received.append(value) }
            return received
        }

        try? await Task.sleep(for: .milliseconds(20))
        queue.append(7)
        try? await Task.sleep(for: .milliseconds(20))
        queue.finish()

        #expect(await consumer.value == [7])
    }

    @Test("Finishing releases a waiting consumer without an element")
    func finishReleasesWaiter() async {
        let queue = BoundedAudioQueue<Int>(capacity: 4)
        let consumer = Task { () -> [Int] in
            var received: [Int] = []
            for await value in queue { received.append(value) }
            return received
        }

        try? await Task.sleep(for: .milliseconds(20))
        queue.finish()

        #expect(await consumer.value == [])
        #expect(queue.isDrained)
    }

    @Test("A finished queue accepts nothing further")
    func finishedQueueRejectsAppends() async {
        let queue = BoundedAudioQueue<Int>(capacity: 4)
        queue.append(1)
        queue.finish()

        #expect(queue.append(2) == 2)

        var received: [Int] = []
        for await value in queue { received.append(value) }
        #expect(received == [1])
    }
}
