<?php
/**
 * Copyright (c) Enalean, 2017. All Rights Reserved.
 *
 * This file is a part of Tuleap.
 *
 * Tuleap is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Tuleap is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Tuleap. If not, see <http://www.gnu.org/licenses/>.
 */

namespace Tuleap\Git;

use HTTPRequest;

/**
 * I am part of a Chain of Responsibility to route Git requests
 */
abstract class RouterLink
{
    /**
     * @var RouterLink|null
     */
    private $next;

    public function __construct()
    {
        $this->next = null;
    }

    /**
     * @param RouterLink $next
     * @return RouterLink
     */
    public function chain(RouterLink $next)
    {
        $this->next = $next;

        return $next;
    }

    public function process(HTTPRequest $request)
    {
        if ($this->next) {
            $this->next->process($request);
        }
    }
}