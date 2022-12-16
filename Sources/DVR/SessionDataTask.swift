import Foundation

final class SessionDataTask: URLSessionDataTask {

    // MARK: - Types

    typealias Completion = (Data?, Foundation.URLResponse?, Error?) -> Void


    // MARK: - Properties

    weak var session: Session!
    let request: URLRequest
    let headersToCheck: [String]
    let completion: Completion?
    private let queue = DispatchQueue(label: "com.venmo.DVR.sessionDataTaskQueue", attributes: [])
    private var interaction: Interaction?

    override var response: Foundation.URLResponse? {
        return interaction?.response
    }

    override var currentRequest: URLRequest? {
        return request
    }


    // MARK: - Initializers

    init(session: Session, request: URLRequest, headersToCheck: [String] = [], completion: (Completion)? = nil) {
        self.session = session
        self.request = request
        self.headersToCheck = headersToCheck
        self.completion = completion
    }


    // MARK: - URLSessionTask

    private var cancelled = false

    override func cancel() {
        cancelled = true
    }

    override func resume() {
        let cassette = session.cassette

        // Find interaction
        if let interaction = session.cassette?.interactionForRequest(request, headersToCheck: headersToCheck) {
            self.interaction = interaction
            // Forward completion
            if let completion = completion {
                queue.async {
                    completion(interaction.responseData, interaction.response, nil)
                }
            }
            session.finishTask(self, interaction: interaction, playback: true)
            return
        }

        if cassette != nil {
            fatalError("[DVR] Invalid request. The request was not found in the cassette.")
        }

        // Cassette is missing. Record.
        if session.recordingEnabled == false {
            fatalError("[DVR] Recording is disabled.")
        }

        let task = session.backingSession.dataTask(with: request, completionHandler: { [weak self] data, response, error in

            //Ensure we have a response
            guard let response = response else {
                return print("[DVR] Failed to record because the task returned a nil response.")
            }

            guard let self = self else {
                return print("[DVR] Something has gone horribly wrong. self == nil")
            }

            // Still call the completion block so the user can chain requests while recording.
            self.queue.async { [weak self] in
                if let self = self, !self.cancelled, self.state != .canceling {
                    self.completion?(data, response, error)
                }
            }

            // Create interaction
            let interaction = Interaction(request: self.request, response: response, responseData: data)
            self.session.finishTask(self, interaction: interaction, playback: false)
        })
        task.resume()
    }
}
