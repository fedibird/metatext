// Copyright © 2020 Metabolist. All rights reserved.

import Combine
import DB
import Foundation
import Mastodon
import MastodonAPI

public struct StatusService {
    public let status: Status
    public let navigationService: NavigationService
    private let mastodonAPIClient: MastodonAPIClient
    private let contentDatabase: ContentDatabase

    init(status: Status, mastodonAPIClient: MastodonAPIClient, contentDatabase: ContentDatabase) {
        self.status = status
        self.navigationService = NavigationService(
            mastodonAPIClient: mastodonAPIClient,
            contentDatabase: contentDatabase,
            status: status.displayStatus)
        self.mastodonAPIClient = mastodonAPIClient
        self.contentDatabase = contentDatabase
    }
}

public extension StatusService {
    func toggleShowContent() -> AnyPublisher<Never, Error> {
        contentDatabase.toggleShowContent(id: status.displayStatus.id)
    }

    func toggleShowAttachments() -> AnyPublisher<Never, Error> {
        contentDatabase.toggleShowAttachments(id: status.displayStatus.id)
    }

    func toggleReblogged() -> AnyPublisher<Never, Error> {
        mastodonAPIClient.request(status.displayStatus.reblogged
                                    ? StatusEndpoint.unreblog(id: status.displayStatus.id)
                                    : StatusEndpoint.reblog(id: status.displayStatus.id))
            .flatMap(contentDatabase.insert(status:))
            .eraseToAnyPublisher()
    }

    func toggleFavorited() -> AnyPublisher<Never, Error> {
        mastodonAPIClient.request(status.displayStatus.favourited
                                    ? StatusEndpoint.unfavourite(id: status.displayStatus.id)
                                    : StatusEndpoint.favourite(id: status.displayStatus.id))
            .flatMap(contentDatabase.insert(status:))
            .eraseToAnyPublisher()
    }

    func toggleBookmarked() -> AnyPublisher<Never, Error> {
        mastodonAPIClient.request(status.displayStatus.bookmarked
                                    ? StatusEndpoint.unbookmark(id: status.displayStatus.id)
                                    : StatusEndpoint.bookmark(id: status.displayStatus.id))
            .flatMap(contentDatabase.insert(status:))
            .eraseToAnyPublisher()
    }

    func togglePinned() -> AnyPublisher<Never, Error> {
        mastodonAPIClient.request(status.displayStatus.pinned ?? false
                                    ? StatusEndpoint.unpin(id: status.displayStatus.id)
                                    : StatusEndpoint.pin(id: status.displayStatus.id))
            .flatMap(contentDatabase.insert(status:))
            .eraseToAnyPublisher()
    }

    func toggleMuted() -> AnyPublisher<Never, Error> {
        mastodonAPIClient.request(status.displayStatus.muted
                                    ? StatusEndpoint.unmute(id: status.displayStatus.id)
                                    : StatusEndpoint.mute(id: status.displayStatus.id))
            .flatMap(contentDatabase.insert(status:))
            .eraseToAnyPublisher()
    }

    func delete() -> AnyPublisher<Status, Error> {
        mastodonAPIClient.request(StatusEndpoint.delete(id: status.displayStatus.id))
            .flatMap { status in contentDatabase.delete(id: status.id).collect().map { _ in status } }
            .eraseToAnyPublisher()
    }

    func deleteAndRedraft() -> AnyPublisher<(Status, Self?), Error> {
        let inReplyToPublisher: AnyPublisher<Self?, Never>

        if let inReplyToId = status.displayStatus.inReplyToId {
            inReplyToPublisher = mastodonAPIClient.request(StatusEndpoint.status(id: inReplyToId))
                .map {
                    Self(status: $0,
                         mastodonAPIClient: mastodonAPIClient,
                         contentDatabase: contentDatabase) as Self?
                }
                .replaceError(with: nil)
                .eraseToAnyPublisher()
        } else {
            inReplyToPublisher = Just(nil).eraseToAnyPublisher()
        }

        return mastodonAPIClient.request(StatusEndpoint.delete(id: status.displayStatus.id))
            .flatMap { status in contentDatabase.delete(id: status.id).collect().map { _ in status } }
            .zip(inReplyToPublisher.setFailureType(to: Error.self))
            .eraseToAnyPublisher()
    }

    func rebloggedByService() -> AccountListService {
        AccountListService(
            endpoint: .rebloggedBy(id: status.id),
            mastodonAPIClient: mastodonAPIClient,
            contentDatabase: contentDatabase)
    }

    func favoritedByService() -> AccountListService {
        AccountListService(
            endpoint: .favouritedBy(id: status.id),
            mastodonAPIClient: mastodonAPIClient,
            contentDatabase: contentDatabase)
    }

    func vote(selectedOptions: Set<Int>) -> AnyPublisher<Never, Error> {
        guard let poll = status.displayStatus.poll else { return Empty().eraseToAnyPublisher() }

        return mastodonAPIClient.request(PollEndpoint.votes(id: poll.id, choices: Array(selectedOptions)))
            .flatMap { contentDatabase.update(id: status.displayStatus.id, poll: $0) }
            .eraseToAnyPublisher()
    }

    func refreshPoll() -> AnyPublisher<Never, Error> {
        guard let poll = status.displayStatus.poll else { return Empty().eraseToAnyPublisher() }

        return mastodonAPIClient.request(PollEndpoint.poll(id: poll.id))
            .flatMap { contentDatabase.update(id: status.displayStatus.id, poll: $0) }
            .eraseToAnyPublisher()
    }
}
