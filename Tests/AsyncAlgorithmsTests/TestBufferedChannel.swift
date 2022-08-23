//
//  TestBufferedChannel.swift
//  
//
//  Created by Thibault WITTEMBERG on 06/08/2022.
//

@testable import AsyncAlgorithms
import XCTest

private struct MockError: Error, Equatable {
  let code: Int
}

// MARK: tests for AsyncBufferedChannel
final class TestBufferedChannel: XCTestCase {
  func testAsyncBufferedChannel_send_queues_elements_and_delivers_to_one_consumer() async {
    let expected = [1, 2, 3, 4, 5]

    // Given
    let sut = AsyncBufferedChannel<Int>()

    // When
    sut.send(1)
    sut.send(2)
    sut.send(3)
    sut.send(4)
    sut.send(5)
    sut.finish()

    var received = [Int]()
    for await element in sut {
      received.append(element)
    }

    // Then
    XCTAssertEqual(received, expected)
  }

  func testAsyncBufferedChannel_send_from_several_producers_queues_elements_and_delivers_to_several_consumers() async {
    let expected1 = Set((1...24))
    let expected2 = Set((25...50))
    let expected = expected1.union(expected2)

    // Given
    let sut = AsyncBufferedChannel<Int>()

    // When
    let sendTask1 = Task {
      for i in expected1 {
        sut.send(i)
      }
    }

    let sendTask2 = Task {
      for i in expected2 {
        sut.send(i)
      }
    }

    await sendTask1.value
    await sendTask2.value

    sut.finish()

    let task1 = Task<[Int], Never> {
      var received = [Int]()
      for await element in sut {
        received.append(element)
      }
      return received
    }

    let task2 = Task<[Int], Never> {
      var received = [Int]()
      for await element in sut {
        received.append(element)
      }
      return received
    }

    let received1 = await task1.value
    let received2 = await task2.value

    let received: Set<Int> = Set(received1).union(received2)

    // Then
    XCTAssertEqual(received, expected)
  }

  func testAsyncBufferedChannel_iteration_ends_when_task_is_cancelled() async {
    let taskCanBeCancelled = expectation(description: "The can be cancelled")
    let taskWasCancelled = expectation(description: "The task was cancelled")
    let iterationHasFinished = expectation(description: "The iteration we finished")

    let sut = AsyncBufferedChannel<Int>()
    sut.send(1)
    sut.send(2)
    sut.send(3)
    sut.send(4)
    sut.send(5)

    let task = Task<Int?, Never> {
      var received: Int?
      for await element in sut {
        received = element
        taskCanBeCancelled.fulfill()
        wait(for: [taskWasCancelled], timeout: 1.0)
      }
      iterationHasFinished.fulfill()
      return received
    }

    wait(for: [taskCanBeCancelled], timeout: 1.0)

    // When
    task.cancel()
    taskWasCancelled.fulfill()

    wait(for: [iterationHasFinished], timeout: 1.0)

    // Then
    let received = await task.value
    XCTAssertEqual(received, 1)
  }

  func testAsyncBufferedChannel_finish_ends_awaiting_consumers_and_immediately_resumes_pastEnd() async {
    let iteration1IsAwaiting = expectation(description: "")
    let iteration1IsFinished = expectation(description: "")

    let iteration2IsAwaiting = expectation(description: "")
    let iteration2IsFinished = expectation(description: "")

    // Given
    let sut = AsyncBufferedChannel<Int>()

    let task1 = Task<Int?, Never> {
      let received = await sut.next {
        iteration1IsAwaiting.fulfill()
      }
      iteration1IsFinished.fulfill()
      return received
    }

    let task2 = Task<Int?, Never> {
      let received = await sut.next {
        iteration2IsAwaiting.fulfill()
      }
      iteration2IsFinished.fulfill()
      return received
    }

    wait(for: [iteration1IsAwaiting, iteration2IsAwaiting], timeout: 1.0)

    // When
    sut.finish()

    wait(for: [iteration1IsFinished, iteration2IsFinished], timeout: 1.0)

    let received1 = await task1.value
    let received2 = await task2.value

    XCTAssertNil(received1)
    XCTAssertNil(received2)

    let iterator = sut.makeAsyncIterator()
    let received = await iterator.next()
    XCTAssertNil(received)
  }

  func testAsyncBufferedChannel_send_does_not_queue_when_already_finished() async {
    // Given
    let sut = AsyncBufferedChannel<Int>()

    // When
    sut.finish()
    sut.send(1)

    // Then
    let iterator = sut.makeAsyncIterator()
    let received = await iterator.next()

    XCTAssertNil(received)
  }

  func testAsyncBufferedChannel_cancellation_immediately_resumes_when_already_finished() async {
    let iterationIsFinished = expectation(description: "The task was cancelled")

    // Given
    let sut = AsyncBufferedChannel<Int>()
    sut.finish()

    // When
    Task {
      for await _ in sut {}
      iterationIsFinished.fulfill()
    }.cancel()

    // Then
    wait(for: [iterationIsFinished], timeout: 1.0)
  }

  func testAsyncBufferedChannel_awaiting_uses_id_for_equatable() {
    // Given
    let awaiting1 = AsyncBufferedChannel<Int>.Awaiting.placeHolder(id: 1)
    let awaiting2 = AsyncBufferedChannel<Int>.Awaiting.placeHolder(id: 2)
    let awaiting3 = AsyncBufferedChannel<Int>.Awaiting.placeHolder(id: 1)

    // When
    // Then
    XCTAssertEqual(awaiting1, awaiting3)
    XCTAssertNotEqual(awaiting1, awaiting2)
  }
}

// MARK: tests for AsyncThrowingBufferedChannel
extension TestBufferedChannel {
  func testAsyncThrowingBufferedChannel_send_queues_elements_and_delivers_to_one_consumer() async throws {
    let expected = [1, 2, 3, 4, 5]

    // Given
    let sut = AsyncThrowingBufferedChannel<Int, Error>()

    // When
    sut.send(1)
    sut.send(2)
    sut.send(3)
    sut.send(4)
    sut.send(5)
    sut.finish()

    var received = [Int]()
    for try await element in sut {
      received.append(element)
    }

    // Then
    XCTAssertEqual(received, expected)
  }

  func testAsyncThrowingBufferedChannel_send_resumes_awaiting() async {
    let iterationIsAwaiting = expectation(description: "Iteration is awaiting")
    let expected = 1

    // Given
    let sut = AsyncThrowingBufferedChannel<Int, Error>()

    let task = Task<Int?, Never> {
      let received = try? await sut.next {
        iterationIsAwaiting.fulfill()
      }
      return received
    }

    wait(for: [iterationIsAwaiting], timeout: 1.0)

    // When
    sut.send(1)

    let received = await task.value

    // Then
    XCTAssertEqual(received, expected)
  }

  func testAsyncThrowingBufferedChannel_send_from_several_producers_queues_elements_and_delivers_to_several_consumers() async throws {
    let expected1 = Set((1...24))
    let expected2 = Set((25...50))
    let expected = expected1.union(expected2)

    // Given
    let sut = AsyncThrowingBufferedChannel<Int, Error>()

    // When
    let sendTask1 = Task {
      for i in expected1 {
        sut.send(i)
      }
    }

    let sendTask2 = Task {
      for i in expected2 {
        sut.send(i)
      }
    }

    await sendTask1.value
    await sendTask2.value

    sut.finish()

    let task1 = Task<[Int], Error> {
      var received = [Int]()
      for try await element in sut {
        received.append(element)
      }
      return received
    }

    let task2 = Task<[Int], Error> {
      var received = [Int]()
      for try await element in sut {
        received.append(element)
      }
      return received
    }

    let received1 = try await task1.value
    let received2 = try await task2.value

    let received: Set<Int> = Set(received1).union(received2)

    // Then
    XCTAssertEqual(received, expected)
  }

  func testAsyncThrowingBufferedChannel_iteration_ends_when_task_is_cancelled() async throws {
    let taskCanBeCancelled = expectation(description: "The can be cancelled")
    let taskWasCancelled = expectation(description: "The task was cancelled")
    let iterationHasFinished = expectation(description: "The iteration we finished")

    let sut = AsyncThrowingBufferedChannel<Int, Error>()
    sut.send(1)
    sut.send(2)
    sut.send(3)
    sut.send(4)
    sut.send(5)

    let task = Task<Int?, Error> {
      var received: Int?
      for try await element in sut {
        received = element
        taskCanBeCancelled.fulfill()
        wait(for: [taskWasCancelled], timeout: 1.0)
      }
      iterationHasFinished.fulfill()
      return received
    }

    wait(for: [taskCanBeCancelled], timeout: 1.0)

    // When
    task.cancel()
    taskWasCancelled.fulfill()

    wait(for: [iterationHasFinished], timeout: 1.0)

    // Then
    let received = try await task.value
    XCTAssertEqual(received, 1)
  }

  func testAsyncThrowingBufferedChannel_fail_queues_failure_and_delivers_to_one_consumer() async {
    // Given
    let sut = AsyncThrowingBufferedChannel<Int, Error>()

    // When
    sut.send(1)
    sut.fail(MockError(code: 1701))

    // Then
    let iterator = sut.makeAsyncIterator()
    do {
      let received = try await iterator.next()
      XCTAssertEqual(received, 1)
      _ = try await iterator.next()
      XCTFail("The iteration should resume with an error")
    } catch {
      XCTAssertEqual(error as? MockError, MockError(code: 1701))
    }
  }

  func testAsyncThrowingBufferedChannel_failure_will_end_future_awaitings() async {
    // Given
    let sut = AsyncThrowingBufferedChannel<Int, Error>()

    // When
    sut.fail(MockError(code: 1701))

    // Then
    let iterator = sut.makeAsyncIterator()
    do {
      _ = try await iterator.next()
      XCTFail("The iteration should resume with an error")
    } catch {
      XCTAssertEqual(error as? MockError, MockError(code: 1701))
    }
  }

  func testAsyncThrowingBufferedChannel_fail_ends_awaiting_consumers_with_error_and_immediately_resumes_pastEnd_with_error() async {
    let iteration1IsAwaiting = expectation(description: "")
    let iteration1HasThrown = expectation(description: "")

    let iteration2IsAwaiting = expectation(description: "")
    let iteration2HasThrown = expectation(description: "")

    // Given
    let sut = AsyncThrowingBufferedChannel<Int, Error>()

    Task<Void, Never> {
      do {
        _ = try await sut.next {
          iteration1IsAwaiting.fulfill()
        }
      } catch {
        iteration1HasThrown.fulfill()
      }
    }

    Task<Void, Never> {
      do {
        _ = try await sut.next {
          iteration2IsAwaiting.fulfill()
        }
      } catch {
        iteration2HasThrown.fulfill()
      }
    }

    wait(for: [iteration1IsAwaiting, iteration2IsAwaiting], timeout: 1.0)

    // When
    sut.fail(MockError(code: 1701))

    // Then
    wait(for: [iteration1HasThrown, iteration2HasThrown], timeout: 1.0)

    let iterator = sut.makeAsyncIterator()
    do {
      _ = try await iterator.next()
      XCTFail("The iteration should resume with an error")
    } catch {
      XCTAssertEqual(error as? MockError, MockError(code: 1701))
    }
  }

  func testAsyncThrowingBufferedChannel_finish_ends_awaiting_consumers_and_immediately_resumes_pastEnd() async throws {
    let iteration1IsAwaiting = expectation(description: "")
    let iteration1IsFinished = expectation(description: "")

    let iteration2IsAwaiting = expectation(description: "")
    let iteration2IsFinished = expectation(description: "")

    // Given
    let sut = AsyncThrowingBufferedChannel<Int, Error>()

    let task1 = Task<Int?, Error> {
      let received = try await sut.next {
        iteration1IsAwaiting.fulfill()
      }
      iteration1IsFinished.fulfill()
      return received
    }

    let task2 = Task<Int?, Error> {
      let received = try await sut.next {
        iteration2IsAwaiting.fulfill()
      }
      iteration2IsFinished.fulfill()
      return received
    }

    wait(for: [iteration1IsAwaiting, iteration2IsAwaiting], timeout: 1.0)

    // When
    sut.finish()

    wait(for: [iteration1IsFinished, iteration2IsFinished], timeout: 1.0)

    let received1 = try await task1.value
    let received2 = try await task2.value

    XCTAssertNil(received1)
    XCTAssertNil(received2)

    let iterator = sut.makeAsyncIterator()
    let received = try await iterator.next()
    XCTAssertNil(received)
  }

  func testAsyncThrowingBufferedChannel_send_does_not_queue_when_already_finished() async throws {
    // Given
    let sut = AsyncThrowingBufferedChannel<Int, Error>()

    // When
    sut.finish()
    sut.send(1)

    // Then
    let iterator = sut.makeAsyncIterator()
    let received = try await iterator.next()

    XCTAssertNil(received)
  }

  func testAsyncThrowingBufferedChannel_cancellation_immediately_resumes_when_already_finished() async throws {
    let iterationIsFinished = expectation(description: "The task was cancelled")

    // Given
    let sut = AsyncThrowingBufferedChannel<Int, Error>()
    sut.finish()

    // When
    Task {
      for try await _ in sut {}
      iterationIsFinished.fulfill()
    }.cancel()

    // Then
    wait(for: [iterationIsFinished], timeout: 1.0)
  }
}
