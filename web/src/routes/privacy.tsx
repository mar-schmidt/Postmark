import { createFileRoute } from "@tanstack/react-router";
import { SiteNav, SiteFooter } from "@/components/SiteNav";

export const Route = createFileRoute("/privacy")({
  component: Privacy,
  head: () => ({
    meta: [
      { title: "Privacy Policy — Postmark" },
      { name: "description", content: "How Postmark handles your data and Gmail account." },
      { property: "og:title", content: "Privacy Policy — Postmark" },
      { property: "og:url", content: "/privacy" },
    ],
    links: [{ rel: "canonical", href: "/privacy" }],
  }),
});

function Privacy() {
  return (
    <div className="min-h-screen bg-background">
      <SiteNav />
      <article className="mx-auto max-w-3xl px-6 py-16 prose-content">
        <h1 className="text-4xl font-bold tracking-tight">Privacy Policy</h1>
        <p className="mt-2 text-sm text-muted-foreground">Last updated: May 14, 2026</p>

        <div className="mt-8 space-y-6 text-foreground/90 leading-relaxed">
          <section>
            <h2 className="text-xl font-semibold mb-2">Overview</h2>
            <p>Postmark is a macOS menu bar app that connects to your Gmail account to display, send, and manage your email. We are committed to protecting your privacy and being transparent about how Postmark handles your data.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Data we access</h2>
            <p>When you sign in with Google, Postmark requests permission to read, send, and modify your Gmail messages. This access is used solely to provide the app's functionality on your device.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Where your data lives</h2>
            <p>Email content is fetched from Gmail and processed locally on your Mac. Postmark does not store, copy, or transmit the contents of your messages to our servers. Your OAuth credentials are stored securely in the macOS Keychain.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Third parties</h2>
            <p>Postmark communicates only with Google's Gmail API. We do not share your data with advertisers, analytics providers, or any other third party.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Revoking access</h2>
            <p>You can disconnect Postmark at any time from your Google Account permissions page or by signing out within the app.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Contact</h2>
            <p>Questions about this policy? Reach us at <a className="text-primary hover:underline" href="mailto:hello@postmark.app">hello@postmark.app</a>.</p>
          </section>
        </div>
      </article>
      <SiteFooter />
    </div>
  );
}
