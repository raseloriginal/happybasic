<?php

declare(strict_types=1);

namespace App\Controllers\Dsr;

use App\Models\DsrTrack;
use Core\Request;
use Core\Response;

/** GPS from the DSR's phone while the app is open. */
final class TrackController extends DsrController
{
    public function status(): Response
    {
        return $this->action(fn(): array => ['tracking' => true, 'token' => csrf_token()]);
    }

    public function store(Request $request): Response
    {
        return $this->action(function () use ($request): array {
            $saved = DsrTrack::store($this->dsr(), array_values((array) $request->input('points', [])));

            return ['saved' => $saved, 'tracking' => true];
        });
    }
}
