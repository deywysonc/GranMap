import React from 'react'

type State = { error?: Error }

export class ErrorBoundary extends React.Component<React.PropsWithChildren, State> {
  state: State = {}

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('granmap.admin.render_error', {
      message: error.message,
      componentStack: info.componentStack,
    })
  }

  render() {
    if (!this.state.error) return this.props.children
    return (
      <main className="fatal-state" role="alert">
        <section className="card fatal-card">
          <span className="eyebrow">RECUPERAÇÃO SEGURA</span>
          <h1>O painel encontrou um problema</h1>
          <p>Os dados não foram alterados. Recarregue o painel para tentar novamente.</p>
          <button className="primary" onClick={() => globalThis.location.reload()}>
            Recarregar painel
          </button>
        </section>
      </main>
    )
  }
}
