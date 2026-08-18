import { createFileRoute } from "@tanstack/react-router";
import { SiteNav, SiteFooter } from "@/components/SiteNav";

export const Route = createFileRoute("/terms")({
  component: Terms,
  head: () => ({
    meta: [
      { title: "Terms of Service — Postmark" },
      { name: "description", content: "Terms governing the use of the Postmark app." },
      { property: "og:title", content: "Terms of Service — Postmark" },
      { property: "og:url", content: "https://postmarkmailapp.com/terms" },
    ],
    links: [{ rel: "canonical", href: "https://postmarkmailapp.com/terms" }],
  }),
});

function Terms() {
  return (
    <div className="min-h-screen bg-background">
      <SiteNav />
      <article className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="text-4xl font-bold tracking-tight">Terms of Service</h1>
        <p className="mt-2 text-sm text-muted-foreground">Last updated: May 14, 2026</p>

        <div className="mt-8 space-y-6 text-foreground/90 leading-relaxed">
          <section>
            <h2 className="text-xl font-semibold mb-2">Acceptance</h2>
            <p>By downloading or using Postmark ("the app"), you agree to these Terms of Service. If you do not agree, please do not use the app.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">License</h2>
            <p>We grant you a personal, non-exclusive, non-transferable license to install and use Postmark on devices you own or control, for personal or internal business use.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Acceptable use</h2>
            <p>You agree not to use Postmark to send spam, harass others, or violate any applicable law. You are responsible for the content you send and receive through the app.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Third-party services</h2>
            <p>Postmark integrates with Gmail, a service provided by Google. Your use of Gmail through Postmark is also subject to Google's Terms of Service.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Disclaimer</h2>
            <p>Postmark is provided "as is" without warranties of any kind. We do not guarantee uninterrupted or error-free operation.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Limitation of liability</h2>
            <p>To the maximum extent permitted by law, Postmark and its creators are not liable for any indirect, incidental, or consequential damages arising from your use of the app.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Changes</h2>
            <p>We may update these terms from time to time. Continued use of the app after changes constitutes acceptance of the new terms.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-2">Contact</h2>
            <p>Questions? Reach us at <a className="text-primary hover:underline" href="mailto:hello@postmark.app">hello@postmark.app</a>.</p>
          </section>
        </div>
      </article>
      <SiteFooter />
    </div>
  );
}
