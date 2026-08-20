import { createFileRoute } from "@tanstack/react-router";
import { SiteNav, SiteFooter } from "@/components/SiteNav";

export const Route = createFileRoute("/privacy")({
  component: Privacy,
  head: () => ({
    meta: [
      { title: "Privacy Policy — Postmark" },
      {
        name: "description",
        content:
          "How Postmark accesses, protects, retains, and deletes your Gmail and Google account data.",
      },
      { property: "og:title", content: "Privacy Policy — Postmark" },
      { property: "og:url", content: "https://postmarkmailapp.com/privacy" },
    ],
    links: [{ rel: "canonical", href: "https://postmarkmailapp.com/privacy" }],
  }),
});

function Privacy() {
  return (
    <div className="min-h-screen bg-background">
      <SiteNav />
      <article className="mx-auto max-w-3xl px-6 py-16 prose-content">
        <h1 className="text-4xl font-bold tracking-tight">Privacy Policy</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Last updated: August 20, 2026
        </p>

        <div className="mt-8 space-y-6 text-foreground/90 leading-relaxed">
          <section>
            <h2 className="text-xl font-semibold mb-2">Overview</h2>
            <p>
              Postmark is a macOS menu bar app that connects to your Gmail
              account so you can read, triage, and reply to email. Postmark runs
              entirely on your Mac. There is no Postmark server, and we operate
              no backend that receives, processes, or stores your email.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">
              Google user data we access
            </h2>
            <p>
              When you sign in with Google, Postmark requests the following
              scopes, each used only to deliver a feature you can see in the
              app:
            </p>
            <ul className="mt-3 space-y-2 list-disc pl-5">
              <li>
                <strong>Gmail — read and modify messages</strong> (
                <code className="text-sm">gmail.modify</code>): to display your
                inbox and threads, mark messages read or unread, and archive
                them.
              </li>
              <li>
                <strong>Gmail — labels</strong> (
                <code className="text-sm">gmail.labels</code>): to list your
                labels so you can choose which ones appear in the app.
              </li>
              <li>
                <strong>Gmail — send</strong> (
                <code className="text-sm">gmail.send</code>): to send the
                replies you write in the app. Postmark never sends mail on your
                behalf without your action.
              </li>
              <li>
                <strong>Contacts — read only</strong> (
                <code className="text-sm">contacts.readonly</code>): to match a
                sender address to their contact photo so messages are easier to
                scan. Postmark reads contact names, email addresses, and photo
                URLs only for this purpose.
              </li>
            </ul>
            <p className="mt-3">
              Postmark does not use Google user data for advertising, profiling,
              credit assessment, resale, or training machine learning or AI
              models.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">
              How we protect your data
            </h2>
            <p>
              Your email is sensitive, and Postmark is built so that the
              smallest possible amount of it is ever stored anywhere. The
              safeguards we apply:
            </p>
            <ul className="mt-3 space-y-2 list-disc pl-5">
              <li>
                <strong>No servers, no copies.</strong> Message content,
                attachments, and contact details are requested directly from
                Google by the app on your Mac and are never routed through,
                logged by, or stored on any Postmark infrastructure. No Postmark
                employee or contractor can access your Google user data, because
                no copy of it ever leaves your device.
              </li>
              <li>
                <strong>Encrypted in transit.</strong> All communication with
                Google APIs uses HTTPS with TLS. Postmark makes no network
                requests carrying your Google user data to any other
                destination.
              </li>
              <li>
                <strong>Credentials encrypted at rest.</strong> OAuth tokens are
                stored in the macOS Keychain, which encrypts them at rest under
                protections managed by the operating system. Each connected
                account gets its own separate Keychain entry. Tokens are never
                written to log files, preference files, or plain text on disk.
              </li>
              <li>
                <strong>We never see your password.</strong> Sign-in happens
                through Google in your system browser using the OAuth 2.0
                authorization code flow with PKCE (via the AppAuth library).
                Postmark never receives, handles, or stores your Google
                password, and cannot present a fake sign-in screen to capture
                one.
              </li>
              <li>
                <strong>Message content stays in memory.</strong> Email bodies,
                subjects, and sender details are held in memory only while the
                app is running and are never written to disk. They are discarded
                when you quit the app.
              </li>
              <li>
                <strong>OS-level isolation.</strong> Postmark runs inside the
                macOS App Sandbox, so its stored data is confined to its own
                container and is not readable by other apps. If you enable
                FileVault, that container is additionally encrypted at rest with
                full-disk encryption.
              </li>
              <li>
                <strong>Least privilege.</strong> We request only the scopes
                listed above, and only at the point where the corresponding
                feature needs them.
              </li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">
              Data retention and deletion
            </h2>
            <p>
              Postmark retains Google user data only for as long as it needs it
              to work on your Mac, and deletes it as described below. Because
              there is no Postmark server, there are no server-side copies,
              backups, or archives of your Google user data to retain.
            </p>
            <ul className="mt-3 space-y-2 list-disc pl-5">
              <li>
                <strong>Message content — not retained.</strong> Messages and
                threads are kept in memory only for the current session and are
                erased when you quit Postmark or sign out. Nothing is cached to
                disk.
              </li>
              <li>
                <strong>Contact data — not retained.</strong> Sender photo
                lookups are held in memory for at most 15 minutes before being
                refreshed, and are erased when you quit the app.
              </li>
              <li>
                <strong>
                  Account details — retained until you remove the account.
                </strong>{" "}
                Postmark stores the email address, display name, and label
                preferences of each connected account in its sandboxed local
                preferences, so it can reopen your accounts the next time you
                launch it. This is deleted as soon as you remove the account or
                sign out.
              </li>
              <li>
                <strong>OAuth tokens — retained until you sign out.</strong>{" "}
                Access and refresh tokens stay in the macOS Keychain so you do
                not have to sign in every time. They are deleted from the
                Keychain immediately when you sign out or remove the account.
              </li>
            </ul>
            <p className="mt-3">
              You can delete your Google user data from Postmark at any time, in
              any of these ways:
            </p>
            <ul className="mt-3 space-y-2 list-disc pl-5">
              <li>
                <strong>Remove one account:</strong> open Settings in Postmark
                and remove the account. Its tokens and stored details are
                deleted right away.
              </li>
              <li>
                <strong>Sign out entirely:</strong> signing out clears every
                account from local storage, deletes all OAuth tokens from the
                Keychain, and clears all message data from memory.
              </li>
              <li>
                <strong>Revoke from Google:</strong> visit{" "}
                <a
                  className="text-primary hover:underline"
                  href="https://myaccount.google.com/permissions"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  your Google Account permissions page
                </a>{" "}
                and remove Postmark. This invalidates its tokens immediately,
                and Postmark loses all access to your data.
              </li>
              <li>
                <strong>Delete the app:</strong> we recommend signing out before
                deleting Postmark, so its stored credentials are removed. If you
                have already deleted the app, revoking access from your Google
                Account permissions page renders any remaining stored tokens
                useless.
              </li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">
              Limited Use disclosure
            </h2>
            <p>
              Postmark's use and transfer of information received from Google
              APIs to any other app will adhere to the{" "}
              <a
                className="text-primary hover:underline"
                href="https://developers.google.com/terms/api-services-user-data-policy"
                target="_blank"
                rel="noopener noreferrer"
              >
                Google API Services User Data Policy
              </a>
              , including the Limited Use requirements.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Third parties</h2>
            <p>
              Postmark does not sell, rent, or share your Google user data with
              any third party. The only service that receives your Google user
              data is Google itself, when the app calls the Gmail and People
              APIs on your behalf.
            </p>
            <p className="mt-3">
              Postmark uses Google Firebase Analytics to understand how the app
              is used and to detect failures. Analytics records app events only
              — for example that a sign-in succeeded, that the inbox refreshed,
              or that a reply failed to send, along with a general error
              category such as "network." It never includes message content,
              subjects, recipients, contacts, email addresses, names, or OAuth
              tokens. Purchases are processed by Apple through the App Store; we
              do not receive or store your payment details.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Children's privacy</h2>
            <p>
              Postmark is not directed at children under 13, and we do not
              knowingly collect data from them.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">
              Changes to this policy
            </h2>
            <p>
              If we change how Postmark handles your data, we will update this
              page and revise the date at the top. Material changes affecting
              Google user data will be reflected here before they take effect.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Contact</h2>
            <p>
              Questions about this policy, or about data protection and
              deletion? Reach us at{" "}
              <a
                className="text-primary hover:underline"
                href="mailto:hello@postmarkmailapp.com"
              >
                hello@postmarkmailapp.com
              </a>
              .
            </p>
          </section>
        </div>
      </article>
      <SiteFooter />
    </div>
  );
}
